import { UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

// Companion 前台页面承载用户授权和采集启停入口。
export default class EntryAbility extends UIAbility {
  onWindowStageCreate(stage: window.WindowStage): void {
    stage.loadContent('pages/Index', (error) => {
      if (error.code !== 0) {
        hilog.error(0x3200, 'AnyDeckCompanion', 'Load page failed: %{public}d', error.code);
      }
    });
  }
}