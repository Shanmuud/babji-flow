const fs = require('node:fs');
const path = require('node:path');
class Avatar {
  constructor(folder, nativeImage) {
    this.file = path.join(folder, 'avatar.png'); this.nativeImage = nativeImage;
    this.rigFile=path.join(folder,'avatar-rig.json');this.rig=null;
    try{if(fs.existsSync(this.file)&&fs.existsSync(this.rigFile))this.rig=JSON.parse(fs.readFileSync(this.rigFile,'utf8'));}catch{}
    this.dataURL = fs.existsSync(this.file) ? nativeImage.createFromPath(this.file).toDataURL() : null;
  }
  import(file) {
    if (!/\.(png|jpe?g|webp)$/i.test(file)) throw new Error('Choose a PNG, JPEG, or WebP photo.');
    if (fs.statSync(file).size > 8 * 1024 * 1024) throw new Error('Choose a photo smaller than 8 MB.');
    const image = this.nativeImage.createFromBuffer(fs.readFileSync(file));
    if (image.isEmpty()) throw new Error('This photo could not be opened. Try a different image.');
    const { width, height } = image.getSize();
    if (width > 8000 || height > 8000) throw new Error('Choose a photo no larger than 8000 pixels per side.');
    const ratio=512/Math.max(width,height);
    const cropped = image.resize({width:Math.max(1,Math.round(width*ratio)),height:Math.max(1,Math.round(height*ratio)),quality:'best'});
    fs.writeFileSync(this.file + '.tmp', cropped.toPNG()); fs.renameSync(this.file + '.tmp', this.file);
    this.rig=null;if(fs.existsSync(this.rigFile))fs.unlinkSync(this.rigFile);
    this.dataURL = cropped.toDataURL(); return this.dataURL;
  }
  setRig(rig){
    if(!rig||!['cx','cy','width','angle','opening'].every(k=>Number.isFinite(rig[k])))throw new Error('Invalid face landmarks');
    // Crop around the detected face, including an off-center face, before animating.
    const source=this.nativeImage.createFromDataURL(this.dataURL),{width,height}=source.getSize(),box=rig.face;
    const side=Math.min(width,height,Math.ceil(Math.max((box.right-box.left)*width,(box.bottom-box.top)*height)*1.35));
    const x=Math.max(0,Math.min(width-side,Math.round((box.left+box.right)*width/2-side/2))),y=Math.max(0,Math.min(height-side,Math.round((box.top+box.bottom)*height/2-side/2)));
    const crop=source.crop({x,y,width:side,height:side}).resize({width:512,height:512,quality:'best'});
    // Correct normalized geometry for rectangular inputs before converting to square crop coordinates.
    const ux=Math.cos(rig.angle)*rig.width*width,uy=Math.sin(rig.angle)*rig.width*height;
    this.rig={version:1,cx:(rig.cx*width-x)/side,cy:(rig.cy*height-y)/side,width:Math.hypot(ux,uy)/side,angle:Math.atan2(uy,ux),opening:rig.opening*height/side};
    fs.writeFileSync(this.file+'.tmp',crop.toPNG());fs.renameSync(this.file+'.tmp',this.file);this.dataURL=crop.toDataURL();
    fs.writeFileSync(this.rigFile+'.tmp',JSON.stringify(this.rig));fs.renameSync(this.rigFile+'.tmp',this.rigFile);
  }
  reset() { if (fs.existsSync(this.file)) fs.unlinkSync(this.file);if(fs.existsSync(this.rigFile))fs.unlinkSync(this.rigFile);this.rig=null;this.dataURL = null; }
}
module.exports = { Avatar };
