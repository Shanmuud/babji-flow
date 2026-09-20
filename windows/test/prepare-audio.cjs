const fs = require('node:fs');
const path = require('node:path');
(async()=>{
  const folder=path.join(__dirname,'../test-artifacts');fs.mkdirSync(folder,{recursive:true});
  const response=await fetch('https://huggingface.co/datasets/Xenova/transformers.js-docs/resolve/main/jfk.wav');
  if(!response.ok)throw new Error(`Fixture download failed: ${response.status}`);
  const bytes=Buffer.from(await response.arrayBuffer());let offset=12,format,channels,rate,bits,data;
  while(offset+8<=bytes.length){const id=bytes.toString('ascii',offset,offset+4),size=bytes.readUInt32LE(offset+4);if(id==='fmt '){format=bytes.readUInt16LE(offset+8);channels=bytes.readUInt16LE(offset+10);rate=bytes.readUInt32LE(offset+12);bits=bytes.readUInt16LE(offset+22);}if(id==='data')data=bytes.subarray(offset+8,offset+8+size);offset+=8+size+(size%2);}
  if(format!==1||bits!==16||!data)throw new Error(`Unexpected fixture format ${format}/${bits}/${channels}/${rate}`);
  const frames=data.length/2/channels, samples=new Float32Array(Math.floor(frames*16000/rate));
  for(let i=0;i<samples.length;i++){const start=Math.floor(i*rate/16000),end=Math.min(frames,Math.floor((i+1)*rate/16000));let sum=0;for(let j=start;j<end;j++)for(let c=0;c<channels;c++)sum+=data.readInt16LE((j*channels+c)*2)/32768;samples[i]=sum/((end-start)*channels);}
  fs.writeFileSync(path.join(folder,'jfk.f32'),Buffer.from(samples.buffer));fs.writeFileSync(path.join(folder,'jfk.wav'),require('../src/core.cjs').wav(samples));console.log(`Prepared public speech fixture: ${samples.length/16000}s`);
})();
