import { window } from '@kit.ArkUI';

export function syncSystemBars(context: Context, darkMode: boolean, backgroundColor?: string): void {
  const bg = backgroundColor || (darkMode ? '#101113' : '#F5F5F5');
  window.getLastWindow(context).then((mainWindow: window.Window) => {
    mainWindow.setWindowBackgroundColor(bg);
    mainWindow.setWindowSystemBarProperties({
      statusBarColor: bg,
      isStatusBarLightIcon: darkMode,
      statusBarContentColor: darkMode ? '#FFFFFF' : '#1F1F1F',
      navigationBarColor: bg,
      isNavigationBarLightIcon: darkMode,
      navigationBarContentColor: darkMode ? '#FFFFFF' : '#1F1F1F'
    });
  }).catch((err: Error) => {
    console.error('同步系统栏颜色失败:', err);
  });
}
