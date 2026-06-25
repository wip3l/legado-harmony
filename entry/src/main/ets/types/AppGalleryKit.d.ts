declare module '@kit.AppGalleryKit' {
  export namespace appInfoManager {
    export interface DynamicIconInfo {
      iconId: string;
      iconName?: string;
      iconUrl?: string;
    }

    export function queryDynamicIcons(): Promise<DynamicIconInfo[]>;

    export function selectDynamicIcon(iconId: string): Promise<void>;

    export function disableDynamicIcon(): Promise<void>;
  }
}
