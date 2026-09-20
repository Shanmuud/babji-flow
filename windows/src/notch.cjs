const path = require('node:path');
class Notch {
  constructor({ BrowserWindow, screen, getSettings, getAvatar, getRig=()=>null, getShortcut = () => 'Ctrl + Shift + Space', headless = false, onClick = () => {}, getPosition = () => null, savePosition = () => {} }) {
    this.onClick = onClick; this.savePosition = savePosition; this.savedPosition = getPosition(); this.manualPosition = !!this.savedPosition;
    this.getRig=getRig; this.screen = screen; this.getSettings = getSettings; this.getAvatar = getAvatar; this.getShortcut = getShortcut; this.headless = headless;
    this.state = { activity: 'idle', label: 'Your voice, anywhere', detail: 'Ctrl + Shift + Space', canCopy: false };
    this.window = new BrowserWindow({ width: 72, height: 72, frame: false, transparent: true, resizable: false, alwaysOnTop: true, skipTaskbar: true, focusable: false, show: false,
      webPreferences: { preload: path.join(__dirname, 'pill-preload.cjs'), contextIsolation: true, nodeIntegration: false, sandbox: true, backgroundThrottling: false } });
    this.window.setAlwaysOnTop(true, 'screen-saver');
    if(this.savedPosition) this.window.setPosition(this.savedPosition.x,this.savedPosition.y);
    this.window.on('closed',()=>{clearTimeout(this.dragTimer);clearTimeout(this.dragWatchdog);clearTimeout(this.timer);clearTimeout(this.idleTimer);});
    this.window.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
    this.window.webContents.on('will-navigate', event => event.preventDefault());
    this.ready = this.window.loadFile(path.join(__dirname, 'pill.html'));
  }
  place(reset = false) {
    if(this.dragOrigin&&!reset)return;
    if(reset&&this.dragOrigin)this.finishDrag(false);
    if (reset) { this.manualPosition = false; this.savePosition(null); }
    if (this.manualPosition) {const [x,y]=this.window.getPosition(),[w,h]=this.window.getSize(),area=this.screen.getDisplayNearestPoint({x,y}).workArea;this.window.setPosition(Math.max(area.x,Math.min(area.x+area.width-w,x)),Math.max(area.y,Math.min(area.y+area.height-h,y)));return;}
    const area = this.screen.getDisplayNearestPoint(this.screen.getCursorScreenPoint()).workArea;
    this.window.setPosition(Math.round(area.x + (area.width - this.window.getSize()[0]) / 2), this.getSettings().notchPosition === 'top' ? area.y + 6 : area.y + area.height - 80);
  }
  show(activity, label, detail = '', canCopy = false) {
    clearTimeout(this.timer);
    if (this.state.activity === 'idle' || activity === 'recording' || activity === 'starting') this.place();
    this.expanded = false;
    if(activity==='idle')this.idleSince=Date.now();
    this.state = { activity, label, detail, canCopy, startedAt:activity==='recording'?Date.now():0 }; this.refresh();
  }
  refresh() {
    clearTimeout(this.idleTimer);const minutes=this.getSettings().idleHideMinutes??3;const remaining=minutes*60000-(Date.now()-(this.idleSince??Date.now()));const idleExpired=this.state.activity==='idle'&&minutes>0&&remaining<=0;
    if(this.state.activity==='idle'&&minutes>0&&remaining>0)this.idleTimer=setTimeout(()=>{if(!this.window.isDestroyed())this.refresh();},remaining);
    const [width,height]=this.window.getSize();if(width!==72||height!==72)this.window.setSize(72,72); this.place();
    this.window.webContents.send('pill', { ...this.state, avatar: this.getAvatar(), rig:this.getRig?.()||null, expanded: !!this.expanded, mouthY: this.getSettings().mouthY, reducedMotion:this.getSettings().reducedMotion });
    if (this.headless || idleExpired || this.state.activity === 'idle' && !this.getSettings().showNotch) this.window.hide();
    else if (!this.window.isVisible()) this.window.showInactive();
  }
  moveDrag() {
    const origin=this.dragOrigin;if(!origin||this.window.isDestroyed())return;
    // Electron cursor and BrowserWindow positions share DIP coordinates. Renderer
    // screenX/Y can change when a transparent window moves or crosses DPI scales.
    const point=this.screen.getCursorScreenPoint(),dx=point.x-origin.point.x,dy=point.y-origin.point.y;
    if(Math.hypot(dx,dy)>4)origin.moved=true;
    if(!origin.moved)return;
    const area=this.screen.getDisplayNearestPoint(point).workArea,[w,h]=this.window.getSize();
    const x=Math.round(Math.max(area.x,Math.min(area.x+area.width-w,origin.position[0]+dx)));
    const y=Math.round(Math.max(area.y,Math.min(area.y+area.height-h,origin.position[1]+dy)));
    const current=this.window.getPosition();this.manualPosition=true;
    if(current[0]!==x||current[1]!==y)this.window.setPosition(x,y);
  }
  drag(action, point) {
    if (!point || !Number.isFinite(point.x) || !Number.isFinite(point.y) || Math.abs(point.x)>100000 || Math.abs(point.y)>100000) return;
    if(action==='drag-start'){
      if(this.dragOrigin)this.finishDrag(false);
      this.dragOrigin={point:this.screen.getCursorScreenPoint(),rendererPoint:point,position:this.window.getPosition(),moved:false};
      const tick=()=>{if(!this.dragOrigin||this.window.isDestroyed())return;this.moveDrag();this.dragTimer=setTimeout(tick,16);};
      this.dragTimer=setTimeout(tick,16);
      this.dragWatchdog=setTimeout(()=>this.finishDrag(false),15000);return;
    }
    const origin=this.dragOrigin;if(!origin||this.window.isDestroyed())return;
    // Only use browser coordinates to suppress a click after a fast drag, never to position the window.
    if(Math.hypot(point.x-origin.rendererPoint.x,point.y-origin.rendererPoint.y)>4)origin.moved=true;
    this.moveDrag();
    if(action==='drag-end'||action==='drag-cancel')this.finishDrag(action==='drag-end');
  }
  finishDrag(allowClick) {
    clearTimeout(this.dragTimer);clearTimeout(this.dragWatchdog);
    const origin=this.dragOrigin;this.dragOrigin=null;if(!origin||this.window.isDestroyed())return;
    if(origin.moved){const [x,y]=this.window.getPosition();this.savePosition({x,y});}
    // A pointer release is never a recording command.
  }
  idle() { this.show('idle', 'Your voice, anywhere', this.getShortcut()); }
  result(label, detail, { error = false, canCopy = false, saved = false } = {}) {
    this.show(error ? 'error' : saved ? 'saved' : 'done', label, detail, canCopy);
    this.timer = setTimeout(() => this.idle(), error?15000:7000);
  }
  level(level) { if (this.state.activity === 'recording') this.window.webContents.send('pill:level', level); }
}
module.exports = { Notch };
