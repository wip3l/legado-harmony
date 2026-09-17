import { audio } from '@kit.AudioKit';
import { media } from '@kit.MediaKit';
import fs from '@ohos.file.fs';
import { TtsAudioSession } from './TtsAudioSession';

export class TtsAvAudioPlayer {
  private readonly audioSessionOwnerPrefix: string = `tts_av_${Date.now()}_${Math.random()}`;
  private activeAudioSessionOwner: string = '';
  private player: media.AVPlayer | null = null;
  private sourceFile: fs.File | null = null;
  private playGeneration: number = 0;
  // Generation that currently owns `player`. A newer play() takes ownership, so an older
  // session finishing later must not release the player the new session is using.
  private playerOwnerGeneration: number = 0;
  private paused: boolean = false;
  private interruptPaused: boolean = false;
  private resumeWaiters: Array<() => void> = [];

  /**
   * Play one synthesized chunk.
   *
   * The player is a resident instance reused by the next chunk. Creating and releasing an
   * AVPlayer per chunk (which is what this used to do) costs far more than the audio itself:
   * the release/prepare/start sequence between two chunks is long enough to be heard as a
   * hard silence between sentences, which is the custom-voice counterpart of the
   * "half a sentence read as a whole sentence" complaint.
   */
  async play(filePath: string, speed: number = 1,
    onPlaybackStart?: (durationMs: number) => void): Promise<void> {
    const generation = ++this.playGeneration;
    this.interruptPaused = false;
    const sourceLength = this.getFileLength(filePath);
    const player = await this.acquirePlayer(generation);
    const sourceFile = fs.openSync(filePath, fs.OpenMode.READ_ONLY);
    this.sourceFile = sourceFile;
    const normalizedSpeed = Math.max(0.125, Math.min(4, speed || 1));
    let keepResident = true;
    const audioSessionOwner = `${this.audioSessionOwnerPrefix}_${generation}`;
    try {
      const initialized = this.waitForInitialized(player, generation);
      // Supplying the complete descriptor is important for downloaded TTS audio.
      // A bare fd can be classified as an unknown-length/live stream by AVPlayer,
      // which rejects playback-rate changes and aborts continuous reading.
      player.fdSrc = { fd: sourceFile.fd, offset: 0, length: sourceLength };
      await initialized;
      if (generation !== this.playGeneration) {
        return;
      }
      player.audioRendererInfo = {
        content: audio.ContentType.CONTENT_TYPE_SPEECH,
        usage: audio.StreamUsage.STREAM_USAGE_AUDIOBOOK,
        rendererFlags: 0
      };
      await player.prepare();
      if (generation !== this.playGeneration) {
        return;
      }
      const ended = new Promise<void>((resolve, reject) => {
        // The initialized waiter has already settled, so its listeners can go now. Clearing
        // everything first also keeps a resident player from accumulating one set of listeners
        // per chunk.
        this.detachListeners(player);
        player.on('stateChange', (state: string) => {
          if (generation !== this.playGeneration) {
            resolve();
            return;
          }
          if (state === 'completed') {
            resolve();
          } else if (state === 'stopped' || state === 'released') {
            reject(new Error(`音频播放被中断：${state}`));
          }
        });
        player.on('error', (error: Error) => {
          if (generation === this.playGeneration) {
            reject(error);
          } else {
            resolve();
          }
        });
        player.on('audioInterrupt', (event: audio.InterruptEvent): void => {
          this.handleAudioInterrupt(player, generation, event);
        });
      });
      const rateApplied = this.applyPlaybackRate(player, normalizedSpeed);
      await this.waitUntilResumed();
      if (generation !== this.playGeneration) {
        return;
      }
      await TtsAudioSession.acquire(audioSessionOwner);
      if (generation !== this.playGeneration) {
        TtsAudioSession.release(audioSessionOwner);
        return;
      }
      this.activeAudioSessionOwner = audioSessionOwner;
      player.setVolume(1);
      if (player.state !== 'playing') {
        await player.play();
      }
      if (this.paused && player.state === 'playing') {
        await player.pause();
      }
      if (onPlaybackStart) {
        try {
          const sourceDuration = player.duration;
          const playbackDuration = sourceDuration > 0 && rateApplied ? sourceDuration / normalizedSpeed : sourceDuration;
          onPlaybackStart(playbackDuration);
        } catch (error) {
          console.warn('[TTS] report av audio duration failed:', error);
          onPlaybackStart(0);
        }
      }
      await ended;
    } catch (error) {
      // A failed chunk must not leave a half-broken player behind for the next one.
      keepResident = false;
      throw error as Error;
    } finally {
      this.detachListeners(player);
      TtsAudioSession.release(audioSessionOwner);
      if (this.activeAudioSessionOwner === audioSessionOwner) {
        this.activeAudioSessionOwner = '';
      }
      if (this.player === player && this.playerOwnerGeneration === generation) {
        if (!keepResident || generation !== this.playGeneration) {
          this.player = null;
          this.playerOwnerGeneration = 0;
          await this.releasePlayer(player);
        } else {
          // Park the player in idle so the next chunk only has to set fdSrc and prepare.
          // Resetting here (rather than when the next chunk starts) keeps the cost inside the
          // tail silence instead of in front of the next sentence. It also runs before the file
          // descriptor is closed so the player still owns a valid source while it tears down.
          try {
            await player.reset();
          } catch (error) {
            console.warn('[TTS] reset av player failed, releasing:', error);
            this.player = null;
            this.playerOwnerGeneration = 0;
            await this.releasePlayer(player);
          }
        }
      }
      if (this.sourceFile === sourceFile) {
        this.sourceFile = null;
      }
      this.closeFile(sourceFile);
    }
  }

  stop(): void {
    this.playGeneration++;
    this.paused = false;
    this.interruptPaused = false;
    this.resolveResumeWaiters();
    TtsAudioSession.release(this.activeAudioSessionOwner);
    this.activeAudioSessionOwner = '';
    const player = this.player;
    const sourceFile = this.sourceFile;
    this.player = null;
    this.playerOwnerGeneration = 0;
    this.sourceFile = null;
    if (player) {
      this.releasePlayer(player).finally(() => {
        this.closeFile(sourceFile);
      });
    } else {
      this.closeFile(sourceFile);
    }
  }

  release(): void {
    this.stop();
  }

  async pause(): Promise<void> {
    if (this.paused) {
      return;
    }
    this.paused = true;
    const player = this.player;
    if (player && player.state === 'playing') {
      await player.pause();
    }
  }

  async resume(): Promise<void> {
    if (!this.paused) {
      return;
    }
    this.paused = false;
    const player = this.player;
    if (player && player.state === 'paused') {
      await TtsAudioSession.acquire(this.activeAudioSessionOwner);
      player.setVolume(1);
      await player.play();
    }
    this.resolveResumeWaiters();
  }

  isPaused(): boolean {
    return this.paused;
  }

  debugState(): string {
    return this.player ? `avPlayer=${this.player.state},paused=${this.paused},generation=${this.playGeneration}` :
      `avPlayer=none,paused=${this.paused}`;
  }

  private waitUntilResumed(): Promise<void> {
    if (!this.paused) {
      return Promise.resolve();
    }
    return new Promise<void>((resolve: () => void) => {
      this.resumeWaiters.push(resolve);
    });
  }

  private resolveResumeWaiters(): void {
    const waiters = this.resumeWaiters.splice(0, this.resumeWaiters.length);
    for (const resolve of waiters) {
      resolve();
    }
  }

  private setDiscreteSpeed(player: media.AVPlayer, speed: number): void {
    try {
      if (speed <= 0.8) {
        player.setSpeed(media.PlaybackSpeed.SPEED_FORWARD_0_75_X);
      } else if (speed <= 1.2) {
        player.setSpeed(media.PlaybackSpeed.SPEED_FORWARD_1_00_X);
      } else if (speed <= 1.75) {
        player.setSpeed(media.PlaybackSpeed.SPEED_FORWARD_1_25_X);
      } else {
        player.setSpeed(media.PlaybackSpeed.SPEED_FORWARD_2_00_X);
      }
    } catch (_) {
    }
  }

  private applyPlaybackRate(player: media.AVPlayer, speed: number): boolean {
    // 1x does not require a rate operation. Avoiding the call also keeps
    // providers that return a stream-like container compatible with AVPlayer.
    if (Math.abs(speed - 1) < 0.01) {
      return false;
    }
    // A prepared local file normally has a finite duration. If the media
    // service still reports an unknown duration, it may reject rate changes
    // with 5400102 (live stream); play it at its encoded/provider speed.
    if (player.duration <= 0) {
      console.warn('[TTS] skip playback rate for unknown-duration audio');
      return false;
    }
    try {
      player.setPlaybackRate(speed);
      return true;
    } catch (_) {
      this.setDiscreteSpeed(player, speed);
      return true;
    }
  }

  private getFileLength(filePath: string): number {
    const size = Number(fs.statSync(filePath).size);
    if (!Number.isSafeInteger(size) || size <= 0) {
      throw new Error('朗读音频文件无效');
    }
    return size;
  }

  private handleAudioInterrupt(player: media.AVPlayer, generation: number,
    event: audio.InterruptEvent): void {
    if (generation !== this.playGeneration || player !== this.player) return;
    console.info(`[TTS] av audio interrupt: hint=${event.hintType},force=${event.forceType},` +
      `state=${player.state},generation=${generation}`);
    const hint = event.hintType;
    if (hint === audio.InterruptHint.INTERRUPT_HINT_DUCK) {
      // Do not alter the application stream gain for advisory duck events.
      // Forced ducking is already applied by the system mixer and is restored
      // by it, so a second app-side gain change only creates an audible step.
      console.info(`[TTS] av duck handled by system mixer: ` +
        `forced=${event.forceType === audio.InterruptForceType.INTERRUPT_FORCE}`);
      return;
    }
    if (hint === audio.InterruptHint.INTERRUPT_HINT_UNDUCK) {
      console.info('[TTS] av unduck received; application stream gain remains unchanged');
      return;
    }
    if (hint === audio.InterruptHint.INTERRUPT_HINT_PAUSE) {
      this.interruptPaused = true;
      if (event.forceType === audio.InterruptForceType.INTERRUPT_SHARE && player.state === 'playing') {
        player.pause().catch(() => {});
      }
      return;
    }
    if (hint === audio.InterruptHint.INTERRUPT_HINT_STOP) {
      this.interruptPaused = false;
      return;
    }
    if (hint === audio.InterruptHint.INTERRUPT_HINT_RESUME) {
      if (this.interruptPaused && !this.paused &&
        (player.state === 'paused' || player.state === 'prepared')) {
        this.interruptPaused = false;
        player.play().catch(() => {});
      } else {
        this.interruptPaused = false;
      }
    }
  }

  /**
   * Return the resident player for a new play session, resetting it when it is still around
   * and creating a fresh one only when reuse is impossible.
   */
  private async acquirePlayer(generation: number): Promise<media.AVPlayer> {
    const existing = this.player;
    if (existing) {
      try {
        this.detachListeners(existing);
        const state = existing.state;
        if (state !== 'idle') {
          await existing.reset();
        }
        if (generation !== this.playGeneration) {
          throw new Error('朗读已停止');
        }
        this.playerOwnerGeneration = generation;
        return existing;
      } catch (error) {
        console.warn('[TTS] reuse av player failed, recreating:', error);
        await this.releaseCurrent();
      }
    }
    const player = await media.createAVPlayer();
    this.player = player;
    this.playerOwnerGeneration = generation;
    console.info(`[TTS] av player created: generation=${generation},state=${player.state}`);
    return player;
  }

  private detachListeners(player: media.AVPlayer | null): void {
    if (!player) {
      return;
    }
    try {
      player.off('stateChange');
    } catch (_) {
    }
    try {
      player.off('error');
    } catch (_) {
    }
    try {
      player.off('audioInterrupt');
    } catch (_) {
    }
  }

  private async releaseCurrent(): Promise<void> {
    const player = this.player;
    const sourceFile = this.sourceFile;
    this.player = null;
    this.playerOwnerGeneration = 0;
    this.sourceFile = null;
    if (player) {
      this.detachListeners(player);
      await this.releasePlayer(player);
    }
    this.closeFile(sourceFile);
  }

  private waitForInitialized(player: media.AVPlayer, generation: number): Promise<void> {
    if (player.state === 'initialized') {
      return Promise.resolve();
    }
    return new Promise<void>((resolve, reject) => {
      const timeoutId = setTimeout(() => {
        reject(new Error('音频播放器初始化超时'));
      }, 5000);
      player.on('stateChange', (state: string) => {
        if (generation !== this.playGeneration) {
          clearTimeout(timeoutId);
          resolve();
          return;
        }
        if (state === 'initialized') {
          clearTimeout(timeoutId);
          resolve();
        } else if (state === 'released' || state === 'error') {
          clearTimeout(timeoutId);
          reject(new Error(`音频播放器初始化失败：${state}`));
        }
      });
      player.on('error', (error: Error) => {
        clearTimeout(timeoutId);
        reject(error);
      });
    });
  }

  private async releasePlayer(player: media.AVPlayer): Promise<void> {
    try {
      if (player.state === 'playing' || player.state === 'paused' || player.state === 'prepared' ||
        player.state === 'completed') {
        await player.stop();
      }
    } catch (_) {
    }
    try {
      await player.release();
    } catch (_) {
    }
  }

  private closeFile(file: fs.File | null): void {
    if (!file) {
      return;
    }
    try {
      fs.closeSync(file);
    } catch (_) {
    }
  }
}
