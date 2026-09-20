/* Audio-reactive mouth deformation shared by the overlay and dashboard. */
class VoiceFace {
 constructor(canvas,source){this.canvas=canvas;this.source=source;this.ctx=canvas.getContext('2d');this.level=0;}
 draw(level,{mouthY=70,reduced=false,custom=false,rig=null}={}){
  const source=this.source;if(!source.complete||!source.naturalWidth)return;
  this.canvas.dataset.painted='true';
  // The bundled face has known mouth coordinates. Photo calibration must not move it.
  mouthY=custom?mouthY:70;
  const key=source.src+':'+mouthY+':'+custom+':'+JSON.stringify(rig);
  if(!this.cache||this.cache.key!==key){
   const base=document.createElement('canvas');base.width=base.height=192;const paint=base.getContext('2d');
   const sx=custom?0:source.naturalWidth*.25,sw=custom?source.naturalWidth:source.naturalWidth*.70;
   const ratio=Math.min(192/sw,192/source.naturalHeight),w=sw*ratio,h=source.naturalHeight*ratio,x=(192-w)/2,y=(192-h)/2,sourceWidth=source.naturalWidth*ratio;
   if(custom){paint.beginPath();paint.arc(96,96,94,0,Math.PI*2);paint.clip();}paint.drawImage(source,sx,0,sw,source.naturalHeight,x,y,w,h);
   const pixels=paint.getImageData(0,0,192,192),field=new Float32Array(192*192),cx=x+sourceWidth*(rig?.cx??(custom?.5:.60))-sx*ratio,cy=y+h*(rig?.cy??mouthY/100),angle=rig?.angle??(custom?0:-.22),cos=Math.cos(angle),sin=Math.sin(angle),mouthWidth=rig?rig.width*w:sourceWidth*.20;const rx=rig?mouthWidth*.85:sourceWidth*.17,ry=rig?Math.max(8,mouthWidth*.55):h*.12;
   for(let py=0;py<192;py++)for(let px=0;px<192;px++){const dx=(px-cx)*cos+(py-cy)*sin,dy=-(px-cx)*sin+(py-cy)*cos,falloff=Math.max(0,1-dx*dx/(rx*rx)-dy*dy/(ry*ry));field[py*192+px]=falloff*falloff;}
   this.cache={key,base,pixels,field,cx,cy,cos,sin,angle,mouthWidth,hinge:(rig?rig.opening*h:mouthWidth*.22)*.38,frame:paint.createImageData(192,192)};
  }
  this.level=reduced||level<.015?0:this.level+(Math.min(1,level*1.2)-this.level)*.6;
  const ctx=this.ctx;ctx.clearRect(0,0,192,192);
  if(this.level<.015){ctx.drawImage(this.cache.base,0,0);return;}
  const {pixels,frame,cx,cy,cos,sin,mouthWidth,hinge}=this.cache;
  for(let py=0;py<192;py++)for(let px=0;px<192;px++){
   const i=py*192+px,dx=px-cx,dy=py-cy,u=dx*cos+dy*sin,localY=-dx*sin+dy*cos;
   const horizontal=Math.max(0,1-Math.pow(u/(mouthWidth*.5),2));
   const opening=this.level*mouthWidth*.13*horizontal;
   // Keep the upper lip and teeth intact; move the lower lip/jaw and reveal an oral gap.
   const inGap=localY>hinge&&localY<hinge+opening;
   if(inGap&&rig&&rig.opening<rig.width*.10&&Math.abs(u)<mouthWidth*.35){frame.data.set([58,28,30,pixels.data[i*4+3]],i*4);continue;}
   const fade=Math.max(0,1-Math.pow(Math.max(0,localY-hinge-opening)/(mouthWidth*.65),2));
   const v=inGap?hinge:localY>=hinge+opening?localY-opening*fade*fade:localY;
   const sx=Math.max(0,Math.min(191,cx+u*cos-v*sin)),sy=Math.max(0,Math.min(191,cy+u*sin+v*cos));
   const x0=Math.floor(sx),y0=Math.floor(sy),x1=Math.min(191,x0+1),y1=Math.min(191,y0+1),fx=sx-x0,fy=sy-y0;
   for(let ch=0;ch<4;ch++)frame.data[i*4+ch]=(pixels.data[(y0*192+x0)*4+ch]*(1-fx)+pixels.data[(y0*192+x1)*4+ch]*fx)*(1-fy)+(pixels.data[(y1*192+x0)*4+ch]*(1-fx)+pixels.data[(y1*192+x1)*4+ch]*fx)*fy;
  }
  ctx.putImageData(frame,0,0);
 }
}
