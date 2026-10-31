const fs=require('node:fs');
const path=require('node:path');
const cp=require('node:child_process');
const root=path.resolve(__dirname,'../demo');fs.mkdirSync(root,{recursive:true});
const rate=44100,seconds=10,n=rate*seconds;
const wav=Buffer.alloc(44+n*2);wav.write('RIFF',0);wav.writeUInt32LE(wav.length-8,4);wav.write('WAVEfmt ',8);wav.writeUInt32LE(16,16);wav.writeUInt16LE(1,20);wav.writeUInt16LE(1,22);wav.writeUInt32LE(rate,24);wav.writeUInt32LE(rate*2,28);wav.writeUInt16LE(2,32);wav.writeUInt16LE(16,34);wav.write('data',36);wav.writeUInt32LE(n*2,40);
for(let i=0;i<n;i++){const t=i/rate,beat=t%0.5;const a=0.45*Math.sin(2*Math.PI*(65*beat+30*(1-Math.exp(-beat*20))))*Math.exp(-beat*14)+0.12*Math.sin(2*Math.PI*220*t)*Math.sin(Math.PI*t/seconds);wav.writeInt16LE(Math.round(Math.max(-1,Math.min(1,a))*24000),44+i*2);}
fs.writeFileSync(path.join(root,'pulse.wav'),wav);
const palettes=[[26,130,180],[200,55,110],[100,170,55]];
for(let k=0;k<3;k++){
 const w=960,h=540,b=Buffer.alloc(w*h*3);
 for(let y=0;y<h;y++)for(let x=0;x<w;x++){
  const d=Math.hypot(x-w*(0.3+k*0.2),y-h*0.45)/w;
  const ring=Math.abs((d*8)%1-0.5)<0.025;
  const mountain=y>h*0.66+Math.sin(x/180+k)*70;
  for(let c=0;c<3;c++)b[(y*w+x)*3+c]=ring?230:Math.round(palettes[k][c]*(mountain?0.2:Math.max(0.1,1-d)));
 }
 const ppm=path.join(root,`frame${k+1}.ppm`);fs.writeFileSync(ppm,Buffer.concat([Buffer.from(`P6\n${w} ${h}\n255\n`),b]));
 cp.execFileSync('ffmpeg',['-v','error','-y','-i',ppm,'-frames:v','1',path.join(root,`frame${k+1}.png`)]);fs.unlinkSync(ppm);
}
const project={version:1,name:'Pulse — demo',audio:'pulse.wav',durationUs:10000000,startUs:0,endUs:10000000,portrait:false,
 images:[1,2,3].map(i=>({path:`frame${i}.png`,scale:1,x:0,y:0,cover:true})),
 markers:[0.5,1,1.5,2,2.5,3,4,5,6,7,8,9].map((t,i)=>({id:`demo-${i}`,timeUs:t*1000000}))};
fs.writeFileSync(path.join(root,'Pulse.tve'),JSON.stringify(project,null,2));
console.log('Generated original demo media in '+root);


