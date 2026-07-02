import { audio } from '@kit.AudioKit';

export class TtsPcmAudioPlayer {
  private renderer: audio.AudioRenderer | null = null;
  private currentSampleRate: audio.AudioSamplingRate = audio.AudioSamplingRate.SAMPLE_RATE_16000;
  private playGeneration: number = 0;
  private writeChain: Promise<void> = Promise.resolve();

  async play(data: ArrayBuffer, sampleRate: number): Promise<void> {
    await this.write(data, sampleRate);
    await this.drain();
  }

  write(data: ArrayBuffer, sampleRate: number): Promise<void> {
    if (!data || data.byteLength === 0) {
      return this.writeChain;
    }
    const audioData = data.slice(0);
    const generation = this.playGeneration;
    this.writeChain = this.writeChain
      .then(async () => {
        if (generation !== this.playGeneration) {
          return;
        }
        const renderer = await this.ensureRenderer(sampleRate);
        if (generation !== this.playGeneration) {
          return;
        }
        if (renderer.state !== audio.AudioState.STATE_RUNNING) {
          await renderer.start();
        }
        if (generation !== this.playGeneration) {
          return;
        }
        await renderer.write(audioData);
      })
      .catch((error: Error) => {
        console.warn('[TTS] write pcm audio failed:', error);
      });
    return this.writeChain;
  }

  async drain(): Promise<void> {
    await this.writeChain;
    const renderer = this.renderer;
    const generation = this.playGeneration;
    if (!renderer || generation !== this.playGeneration ||
      renderer.state !== audio.AudioState.STATE_RUNNING) {
      return;
    }
    await renderer.drain();
  }

  stop(): void {
    this.playGeneration++;
    this.writeChain = Promise.resolve();
    const renderer = this.renderer;
    this.renderer = null;
    if (!renderer) {
      return;
    }
    this.releaseRenderer(renderer);
  }

  release(): void {
    this.stop();
  }

  debugState(): string {
    if (!this.renderer) {
      return 'renderer=none';
    }
    return `renderer=${this.audioStateName(this.renderer.state)},sampleRate=${this.currentSampleRate},generation=${this.playGeneration}`;
  }

  private audioStateName(state: audio.AudioState): string {
    switch (state) {
      case audio.AudioState.STATE_RUNNING:
        return 'STATE_RUNNING';
      case audio.AudioState.STATE_STOPPED:
        return 'STATE_STOPPED';
      case audio.AudioState.STATE_RELEASED:
        return 'STATE_RELEASED';
      case audio.AudioState.STATE_PAUSED:
        return 'STATE_PAUSED';
      default:
        return `STATE_${state}`;
    }
  }

  private async ensureRenderer(sampleRate: number): Promise<audio.AudioRenderer> {
    const nextSampleRate = this.toAudioSampleRate(sampleRate);
    if (this.renderer && this.currentSampleRate === nextSampleRate &&
      this.renderer.state !== audio.AudioState.STATE_RELEASED &&
      this.renderer.state !== audio.AudioState.STATE_STOPPED) {
      return this.renderer;
    }
    const previousRenderer = this.renderer;
    this.renderer = null;
    if (previousRenderer) {
      await this.releaseRenderer(previousRenderer);
    }
    this.currentSampleRate = nextSampleRate;
    const options: audio.AudioRendererOptions = {
      streamInfo: {
        samplingRate: nextSampleRate,
        channels: audio.AudioChannel.CHANNEL_1,
        sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
        encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW,
        channelLayout: audio.AudioChannelLayout.CH_LAYOUT_MONO
      },
      rendererInfo: {
        content: audio.ContentType.CONTENT_TYPE_SPEECH,
        usage: audio.StreamUsage.STREAM_USAGE_AUDIOBOOK,
        rendererFlags: 0
      }
    };
    this.renderer = await audio.createAudioRenderer(options);
    console.info(`[TTS] audio renderer created: ${this.debugState()}`);
    return this.renderer;
  }

  private async releaseRenderer(renderer: audio.AudioRenderer): Promise<void> {
    try {
      if (renderer.state === audio.AudioState.STATE_RUNNING ||
        renderer.state === audio.AudioState.STATE_PAUSED) {
        await renderer.stop();
      }
    } catch (error) {
      console.warn('[TTS] stop pcm renderer failed:', error);
    }
    try {
      if (renderer.state !== audio.AudioState.STATE_RELEASED) {
        await renderer.release();
      }
    } catch (error) {
      console.warn('[TTS] release pcm renderer failed:', error);
    }
  }

  private toAudioSampleRate(sampleRate: number): audio.AudioSamplingRate {
    switch (sampleRate) {
      case 8000:
        return audio.AudioSamplingRate.SAMPLE_RATE_8000;
      case 11025:
        return audio.AudioSamplingRate.SAMPLE_RATE_11025;
      case 12000:
        return audio.AudioSamplingRate.SAMPLE_RATE_12000;
      case 22050:
        return audio.AudioSamplingRate.SAMPLE_RATE_22050;
      case 24000:
        return audio.AudioSamplingRate.SAMPLE_RATE_24000;
      case 32000:
        return audio.AudioSamplingRate.SAMPLE_RATE_32000;
      case 44100:
        return audio.AudioSamplingRate.SAMPLE_RATE_44100;
      case 48000:
        return audio.AudioSamplingRate.SAMPLE_RATE_48000;
      case 96000:
        return audio.AudioSamplingRate.SAMPLE_RATE_96000;
      case 16000:
      default:
        return audio.AudioSamplingRate.SAMPLE_RATE_16000;
    }
  }
}
