/*
 * Copyright (c) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the 'License');
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an 'AS IS' BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { Logger } from './Logger';
import { WantAgent, wantAgent } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

export function startContinuousTask(context: Context | undefined) {
  if (!context) {
    return;
  }
  let wantAgentInfo: wantAgent.WantAgentInfo = {
    wants: [
      {
        bundleName: 'com.anydeck.harmonycompanion',
        abilityName: 'EntryAbility'
      }
    ],
    actionType: wantAgent.OperationType.START_ABILITY,
    requestCode: 0,
    actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
  };

  wantAgent.getWantAgent(wantAgentInfo)
    .then((wantAgentObj: WantAgent) => {
      let list: Array<string> = ['audioRecording'];
      backgroundTaskManager.startBackgroundRunning(context, list, wantAgentObj)
        .then(() => {
          Logger.info('Operation startBackgroundRunning succeeded');
        })
        .catch((error: BusinessError) => {
          Logger.error(`Failed to Operation startBackgroundRunning. code is ${error.code} message is ${error.message}`);
        });
    }).catch((error: BusinessError) => {
    Logger.error(`Failed to Operation getWantAgent. code is ${(error as BusinessError).code} message is ${(error as BusinessError).message}`);
  });
}

export function stopContinuousTask(context: Context | undefined) {
  if (!context) {
    return;
  }
  backgroundTaskManager.stopBackgroundRunning(context).then(() => {
    Logger.info(`Succeeded in operationing stopBackgroundRunning.`);
  }).catch((err: BusinessError) => {
    Logger.error(`Failed to operation stopBackgroundRunning. code is ${err.code}, message is ${err.message}`);
  });
}