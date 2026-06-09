declare module '@kit.CoreSpeechKit' {
  export namespace textToSpeech {
    export interface BusinessError {
      code?: number;
      message?: string;
      name?: string;
    }

    export type Callback<T> = (data: T) => void;
    export type ErrorCallback<T> = (err: T) => void;
    export type AsyncCallback<T> = (err: BusinessError | null | undefined, data: T) => void;

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

    export interface VoiceDownload {
      requestId: string;
      language: string;
      person: number;
      style: string;
    }

    export interface DownloadResponse {
      requestId: string;
      on(type: 'start', callback: Callback<string>): void;
      off(type: 'start', callback?: Callback<string>): void;
      on(type: 'progress', callback: Callback<string>): void;
      off(type: 'progress', callback?: Callback<string>): void;
      on(type: 'complete', callback: Callback<VoiceInfo>): void;
      off(type: 'complete', callback?: Callback<VoiceInfo>): void;
      on(type: 'cancel', callback: Callback<string>): void;
      off(type: 'cancel', callback?: Callback<string>): void;
      on(type: 'error', callback: ErrorCallback<BusinessError>): void;
      off(type: 'error', callback?: ErrorCallback<BusinessError>): void;
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
    export function listVoices(queryParams: VoiceQuery): Promise<Array<VoiceInfo>>;
    export function downloadVoice(downloadParams: VoiceDownload, callback: AsyncCallback<DownloadResponse>): void;
  }
}
