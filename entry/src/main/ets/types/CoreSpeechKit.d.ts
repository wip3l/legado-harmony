declare module '@kit.CoreSpeechKit' {
  export namespace textToSpeech {
    export interface CreateEngineParams {
      language: string;
      person: number;
      online: number;
      extraParams?: Record<string, Object>;
    }

    export interface SpeakParams {
      requestId: string;
      extraParams?: Record<string, Object>;
    }

    export interface VoiceQuery {
      requestId: string;
      online: number;
      extraParams?: Record<string, Object>;
    }

    export interface VoiceInfo {
      language: string;
      person: number;
      style: string;
      gender: string;
      description: string;
      status?: string;
    }

    export interface StartResponse {
      audioType?: string;
      sampleRate?: number;
      sampleBit?: number;
      audioChannel?: number;
      compressRate?: number;
    }

    export interface CompleteResponse {
      type: number;
      message?: string;
    }

    export interface StopResponse {
      type: number;
      message?: string;
    }

    export interface SynthesisResponse {
      sequence: number;
      audioType: string;
    }

    export interface SpeakListener {
      onStart?: (utteranceId: string, response: StartResponse) => void;
      onComplete?: (utteranceId: string, response: CompleteResponse) => void;
      onStop?: (utteranceId: string, response: StopResponse) => void;
      onData?: (utteranceId: string, audio: ArrayBuffer, response: SynthesisResponse) => void;
      onError?: (utteranceId: string, errorCode: number, errorMessage: string) => void;
    }

    export interface TextToSpeechEngine {
      speak(text: string, speakParams: SpeakParams): void;
      setListener(listener: SpeakListener): void;
      listVoices(params: VoiceQuery): Promise<Array<VoiceInfo>>;
      stop(): void;
      isBusy(): boolean;
      shutdown(): void;
    }

    export function createEngine(createEngineParams: CreateEngineParams): Promise<TextToSpeechEngine>;
  }
}
