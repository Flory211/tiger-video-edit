const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process');
const root=path.resolve(__dirname,'../demo');
cp.execFileSync('ffmpeg',['-v','error','-y','-framerate','3','-i',path.join(root,'frame%d.png'),'-vf',"zoompan=z='1+on*0.002':d=20:s=640x360:fps=30",'-c:v','libx264','-pix_fmt','yuv420p',path.join(root,'motion.mp4')]);
cp.execFileSync('ffmpeg',['-v','error','-y','-framerate','3','-i',path.join(root,'frame%d.png'),'-loop','0',path.join(root,'motion.gif')]);
const p=JSON.parse(fs.readFileSync(path.join(root,'Pulse.tve'),'utf8').replace(/^\uFEFF/,''));
p.version=2;p.name='Tiger 2 — effects & motion';
p.images=[{path:'frame1.png',effects:{zoom:.45,flash:.3}},{path:'motion.mp4',effects:{rgb:.4,glitch:.25},durationUs:2000000},{path:'motion.gif',effects:{shake:.25,glow:.4},durationUs:990000}].map(s=>({scale:1,x:0,y:0,cover:true,effectDurationUs:450000,sourceStartUs:0,durationUs:0,...s}));
p.captions=[{id:'title',text:'TIGER VIDEO EDIT 2',startUs:0,endUs:3000000,x:.5,y:.78,fontSize:90,color:0xffc6f36a},{id:'offline',text:'Effects • Video • GIF • Captions',startUs:3000000,endUs:7000000,x:.5,y:.85,fontSize:56,color:0xffffffff}];
fs.writeFileSync(path.join(root,'Pulse-v2.tve'),JSON.stringify(p,null,2));console.log('Original v2 demo generated');
