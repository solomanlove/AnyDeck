import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { startContinuousTask, stopContinuousTask } from '../utils/BackgroundTaskUtil';
import bridge from 'libentry.so';
import { CameraPreview } from './CameraPreview';

// 设备侧仅连接本机 HDC 反向端口，收到系统录制授权后转发 PCM。
@Entry
@Component
struct Index {
  @State status: string = '等待桌面端监听 26733 端口';
  @State running: boolean = false;
  @State cameraOpen: boolean = false;
  private context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;

  async start(microphone: boolean): Promise<void> {
    if (this.running) {
      this.stop();
    }
    if (microphone) {
      const permission: Permissions = 'ohos.permission.MICROPHONE';
      try {
        const result = await abilityAccessCtrl.createAtManager()
          .requestPermissionsFromUser(this.context, [permission]);
        if (result.authResults[0] !== 0) {
          this.status = '麦克风权限未授予';
          return;
        }
      } catch (error) {
        this.status = '麦克风授权失败: ' + (error as BusinessError).code;
        return;
      }
    }
    const result: number = bridge.startAudio(26733, microphone);
    if (result !== 0) {
      this.status = '采集启动失败: ' + result;
      return;
    }
    this.running = true;
    this.status = microphone ? '正在转发麦克风 PCM' : '正在转发设备内音频 PCM';
    startContinuousTask(this.context);
  }

  stop(): void {
    bridge.stopAudio();
    stopContinuousTask(this.context);
    this.running = false;
    this.status = '已停止';
  }

  aboutToDisappear(): void {
    if (this.running) {
      this.stop();
    }
  }

  build() {
    Column({ space: 16 }) {
      Text('AnyDeck HarmonyOS 音频原型')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
      Text(this.status)
        .fontSize(15)
      Button('只转发设备内音频')
        .onClick(() => { this.start(false); })
      Button('转发麦克风')
        .onClick(() => { this.start(true); })
      Button('停止')
        .enabled(this.running)
        .onClick(() => { this.stop(); })
      Button(this.cameraOpen ? '关闭摄像头' : '预览摄像头')
        .onClick(() => { this.cameraOpen = !this.cameraOpen; })
      if (this.cameraOpen) {
        CameraPreview()
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(24)
  }
}
