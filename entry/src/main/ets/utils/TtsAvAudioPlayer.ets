import { audio } from '@kit.AudioKit';
import { media } from '@kit.MediaKit';

export class TtsAvAudioPlayer {
  private player: media.AVPlayer | null = null;
  private playGeneration: number = 0;

  async play(filePath: string, speed: number = 1): Promise<void> {
    const generation = ++this.playGeneration;
    await this.releaseCurrent();
    const player = await media.createAVPlayer();
    this.player = player;
    const normalizedSpeed = Math.max(0.125, Math.min(4, speed || 1));
    player.audioRendererInfo = {
      content: audio.ContentType.CONTENT_TYPE_SPEECH,
      usage: audio.StreamUsage.STREAM_USAGE_AUDIOBOOK,
      rendererFlags: 0
    };
    const ended = new Promise<void>((resolve, reject) => {
      player.on('stateChange', (state: string) => {
        if (generation !== this.playGeneration) {
          resolve();
          return;
        }
        if (state === 'completed' || state === 'stopped' || state === 'released') {
          resolve();
        }
      });
      player.on('error', (error: Error) => {
        if (generation === this.playGeneration) {
          reject(error);
        } else {
          resolve();
        }
      });
    });
    player.url = `file://${filePath}`;
    await player.prepare();
    if (generation !== this.playGeneration) {
      await this.releasePlayer(player);
      return;
    }
    try {
      player.setPlaybackRate(normalizedSpeed);
    } catch (_) {
      this.setDiscreteSpeed(player, normalizedSpeed);
    }
    await player.play();
    await ended;
  }

  stop(): void {
    this.playGeneration++;
    const player = this.player;
    this.player = null;
    if (player) {
      this.releasePlayer(player);
    }
  }

  release(): void {
    this.stop();
  }

  debugState(): string {
    return this.player ? `avPlayer=${this.player.state},generation=${this.playGeneration}` : 'avPlayer=none';
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

  private async releaseCurrent(): Promise<void> {
    const player = this.player;
    this.player = null;
    if (player) {
      await this.releasePlayer(player);
    }
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
}
