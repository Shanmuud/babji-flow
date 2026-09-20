'use strict';
// One-shot, on-device detection when a photo is chosen. Never uses a camera.
let faceDetectorPromise;
async function detectAvatarMouth(dataURL){
 if(!faceDetectorPromise)faceDetectorPromise=(async()=>{
  const {FaceLandmarker,FilesetResolver}=await import('../assets/vision/vision_bundle.mjs');
  const files=await FilesetResolver.forVisionTasks(new URL('../assets/vision/wasm',location.href).href);
  return FaceLandmarker.createFromOptions(files,{baseOptions:{modelAssetPath:new URL('../assets/vision/face_landmarker.task',location.href).href,delegate:'CPU'},runningMode:'IMAGE',numFaces:2,minFaceDetectionConfidence:.45,minFacePresenceConfidence:.45});
 })().catch(error=>{faceDetectorPromise=null;throw error;});
 const detector=await faceDetectorPromise,image=new Image();image.src=dataURL;await image.decode();
 const faces=detector.detect(image).faceLandmarks;
 if(faces.length!==1)throw new Error(faces.length?'Choose a picture with one face.':'No face detected. Try a clear, front-facing photo.');
 const p=faces[0],left=p[61],right=p[291],upper=p[13],lower=p[14];
 const width=Math.hypot(right.x-left.x,right.y-left.y),angle=Math.atan2(right.y-left.y,right.x-left.x);
 if(width<.025||width>.65)throw new Error('Mouth detection was uncertain. Try a closer face photo.');
 const xs=p.map(v=>v.x),ys=p.map(v=>v.y);
 return {version:1,cx:(left.x+right.x)/2,cy:(upper.y+lower.y)/2,width,angle,opening:Math.hypot(lower.x-upper.x,lower.y-upper.y),face:{left:Math.max(0,Math.min(...xs)),top:Math.max(0,Math.min(...ys)),right:Math.min(1,Math.max(...xs)),bottom:Math.min(1,Math.max(...ys))}};
}
