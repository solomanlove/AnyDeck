import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { camera } from '@kit.CameraKit';

// 仅在 Companion 前台显示摄像头预览；关闭组件时释放会话和相机输入。
@Component
export struct CameraPreview {
  @State private status: string = '等待摄像头授权';
  @State private front: boolean = false;
  private context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
  private surface: XComponentController = new XComponentController();
  private manager?: camera.CameraManager;
  private input?: camera.CameraInput;
  private output?: camera.PreviewOutput;
  private session?: camera.PhotoSession;
  private busy: boolean = false;
  private opened: boolean = false;
  private releasing?: Promise<void>;

  private async requestCamera(): Promise<boolean> {
    const permission: Permissions = 'ohos.permission.CAMERA';
    try {
      const result = await abilityAccessCtrl.createAtManager()
        .requestPermissionsFromUser(this.context, [permission]);
      return result.authResults[0] === 0;
    } catch (error) {
      this.status = '摄像头授权失败: ' + (error as BusinessError).code;
      return false;
    }
  }

  private async start(): Promise<void> {
    if (this.busy || !this.opened) {
      return;
    }
    this.busy = true;
    try {
      if (!await this.requestCamera()) {
        this.status = '摄像头权限未授予';
        return;
      }
      if (!this.opened) {
        return;
      }
      this.manager = camera.getCameraManager(this.context);
      const position = this.front
        ? camera.CameraPosition.CAMERA_POSITION_FRONT
        : camera.CameraPosition.CAMERA_POSITION_BACK;
      const device = this.manager.getSupportedCameras()
        .find((item: camera.CameraDevice) => item.cameraPosition === position);
      if (!device) {
        this.status = '当前设备没有所选镜头';
        return;
      }
      this.input = this.manager.createCameraInput(device);
      await this.input.open();
      this.session = this.manager.createSession(camera.SceneMode.NORMAL_PHOTO) as camera.PhotoSession;
      if (this.session.canPreconfig(camera.PreconfigType.PRECONFIG_720P)) {
        this.session.preconfig(camera.PreconfigType.PRECONFIG_720P,
          camera.PreconfigRatio.PRECONFIG_RATIO_16_9);
      }
      this.output = this.manager.createPreviewOutput(this.surface.getXComponentSurfaceId());
      this.session.beginConfig();
      this.session.addInput(this.input);
      this.session.addOutput(this.output);
      await this.session.commitConfig();
      await this.session.start();
      this.status = this.front ? '前置镜头预览中' : '后置镜头预览中';
    } catch (error) {
      this.status = '摄像头启动失败: ' + (error as BusinessError).code;
      await this.release();
    } finally {
      this.busy = false;
    }
  }

  private async release(): Promise<void> {
    if (this.releasing) {
      await this.releasing;
      return;
    }
    this.releasing = this.releaseCore();
    await this.releasing;
    this.releasing = undefined;
  }

  private async releaseCore(): Promise<void> {
    const session = this.session;
    const output = this.output;
    const input = this.input;
    this.session = undefined;
    this.output = undefined;
    this.input = undefined;
    this.manager = undefined;
    try {
      await session?.stop();
      await output?.release();
      await input?.close();
      await session?.release();
    } catch (error) {
      this.status = '摄像头清理失败: ' + (error as BusinessError).code;
    }
  }

  private async switchCamera(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    await this.release();
    this.front = !this.front;
    this.busy = false;
    await this.start();
  }

  aboutToDisappear(): void {
    this.opened = false;
    this.release();
  }

  build() {
    Column({ space: 8 }) {
      Text(this.status).fontSize(14)
      XComponent({
        type: XComponentType.SURFACE,
        controller: this.surface
      })
        .width('100%')
        .height(300)
        .onLoad(() => {
          this.opened = true;
          this.start();
        })
        .onDestroy(() => {
          this.opened = false;
          this.release();
        })
      Button(this.front ? '切换到后置镜头' : '切换到前置镜头')
        .onClick(() => { this.switchCamera(); })
    }
    .width('100%')
  }
}
