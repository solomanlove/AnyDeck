// 原型只模拟界面状态；所有传输与设备均为演示数据。
const $ = (id) => document.getElementById(id);
const shade = $('shade');
let pendingFile = null;
let history = [];

function button(label, action, primary = false) {
  const el = document.createElement('button');
  el.type = 'button';
  el.textContent = label;
  if (primary) el.className = 'primary';
  el.addEventListener('click', action);
  return el;
}

function dialog({ icon = '↗', eyebrow = 'TRANSFER', title, text, summary = '', actions = [] }) {
  $('dialogIcon').textContent = icon;
  $('dialogEyebrow').textContent = eyebrow;
  $('dialogTitle').textContent = title;
  $('dialogText').textContent = text;
  $('fileSummary').textContent = summary;
  $('fileSummary').classList.toggle('hidden', !summary);
  $('dialogActions').replaceChildren(...actions.map(([label, action, primary]) => button(label, action, primary)));
  shade.classList.remove('hidden');
  shade.setAttribute('aria-hidden', 'false');
}
function close() { shade.classList.add('hidden'); shade.setAttribute('aria-hidden', 'true'); }
function record(direction, name, result) {
  history.unshift({ direction, name, result, time: new Date().toLocaleTimeString('zh-CN', {hour:'2-digit', minute:'2-digit'}) });
  $('recentList').replaceChildren(...history.slice(0, 3).map((item) => {
    const row = document.createElement('div'); row.className = 'record';
    const badge = document.createElement('span'); badge.className = 'badge'; badge.textContent = item.direction === '发送' ? '↗' : '↙';
    const detail = document.createElement('div');
    const nameText = document.createElement('b'); nameText.textContent = item.name;
    const meta = document.createElement('small'); meta.textContent = `${item.direction} · ${item.time}`;
    detail.append(nameText, meta);
    const status = document.createElement('span'); status.className = 'right'; status.textContent = item.result;
    row.append(badge, detail, status); return row;
  }));
}
function prepare(file) {
  if (!file) return;
  pendingFile = file;
  const size = file.size ? `${(file.size / 1024).toFixed(1)} KB` : '演示文件';
  dialog({ title: '发送到 nova 12 Ultra', text: '请确认目标设备和文件。传输开始后，手机端需要确认接收。', summary: `${file.name} · ${size}`, actions: [
    ['取消', close], ['发送', () => {
      dialog({icon:'↗', title:'正在等待手机接收', text:'已向 nova 12 Ultra 发出请求…', summary:file.name, actions:[['取消发送', close], ['模拟发送完成', () => {close();record('发送', file.name, '已完成');} , true]]});
    }, true]
  ]});
}
$('pickBtn').addEventListener('click', () => $('fileInput').click());
$('device').addEventListener('click', () => $('fileInput').click());
$('device').addEventListener('keydown', e => {if (e.key === 'Enter' || e.key === ' ') $('fileInput').click();});
$('fileInput').addEventListener('change', e => prepare(e.target.files[0]));
$('closeDialog').addEventListener('click', close);
shade.addEventListener('click', e => {if (e.target === shade) close();});
document.addEventListener('keydown', e => {if (e.key === 'Escape') close();});
const zone = $('dropZone');
zone.addEventListener('dragover', e => {e.preventDefault();zone.classList.add('dragging');});
zone.addEventListener('dragleave', e => {if (!zone.contains(e.relatedTarget)) zone.classList.remove('dragging');});
zone.addEventListener('drop', e => {e.preventDefault();zone.classList.remove('dragging');prepare(e.dataTransfer.files[0]);});
$('historyBtn').addEventListener('click', () => dialog({icon:'▤',eyebrow:'HISTORY',title:'互传记录',text:'按发送和接收查看任务。此原型只显示当前页面内模拟的记录。',summary:history.length ? history.map(x => `${x.direction} ${x.name} · ${x.result}`).join('　/　') : '暂无传输记录',actions:[['关闭',close]]}));
$('helpBtn').addEventListener('click', () => dialog({icon:'?',eyebrow:'HELP',title:'找不到设备？',text:'保持手机解锁，在控制中心打开“华为分享”并设为“所有人可见”；确认 Mac 和手机处于同一 Wi-Fi。',actions:[['知道了',close,true]]}));
function settings() {dialog({icon:'⚙',eyebrow:'SETTINGS',title:'互传设置',text:'正式版提供本机名称、接收保存位置、通知与权限状态。网络参数由系统自动管理。',summary:'保存位置：下载 / AnyDeck 互传',actions:[['关闭',close],['模拟收到文件',incoming,true]]});}
$('settingsNav').addEventListener('click', settings);
$('identityMenu').addEventListener('click', settings);
function incoming() {dialog({icon:'↙',eyebrow:'INCOMING',title:'nova 12 Ultra 想发送文件',text:'接收后文件将保存到“下载 / AnyDeck 互传”。',summary:'holiday-photo.jpg · 384 KB',actions:[['拒绝',close],['接收',() => {close();record('接收','holiday-photo.jpg','已接收');dialog({icon:'✓',title:'接收完成',text:'文件已保存。正式版可直接在 Finder 中显示。',summary:'下载 / AnyDeck 互传 / holiday-photo.jpg',actions:[['完成',close,true]]});},true]]});}
