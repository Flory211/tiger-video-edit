const fs=require('node:fs'),path=require('node:path'),zlib=require('node:zlib');
function crc(b){let c=0xffffffff;for(const x of b){c^=x;for(let i=0;i<8;i++)c=(c>>>1)^((c&1)?0xedb88320:0);}return (c^0xffffffff)>>>0;}
function chunk(type,data){const t=Buffer.from(type),b=Buffer.alloc(data.length+12);b.writeUInt32BE(data.length);t.copy(b,4);data.copy(b,8);b.writeUInt32BE(crc(Buffer.concat([t,data])),data.length+8);return b;}
function png(n){const raw=Buffer.alloc((n*4+1)*n);for(let y=0;y<n;y++)for(let x=0;x<n;x++){
 const u=x/n,v=y/n;const L=(u>.2&&u<.8&&v>.23&&v<.36)||(u>.43&&u<.57&&v>.23&&v<.78);
 const beat=(u>.51&&u<.59&&v>.37&&v<.53)||(u>.65&&u<.73&&v>.22&&v<.53);
 const at=y*(n*4+1)+1+x*4;[L||beat?198:20,L||beat?243:24,L||beat?106:31,255].forEach((c,i)=>raw[at+i]=c);
 }const head=Buffer.alloc(13);head.writeUInt32BE(n);head.writeUInt32BE(n,4);head[8]=8;head[9]=6;
 return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',head),chunk('IDAT',zlib.deflateSync(raw)),chunk('IEND',Buffer.alloc(0))]);}
const root=path.resolve(__dirname,'..');const img=png(256),ico=Buffer.alloc(22);ico.writeUInt16LE(1,2);ico.writeUInt16LE(1,4);ico.writeUInt16LE(1,10);ico.writeUInt16LE(32,12);ico.writeUInt32LE(img.length,14);ico.writeUInt32LE(22,18);
fs.writeFileSync(path.join(root,'windows/runner/resources/app_icon.ico'),Buffer.concat([ico,img]));
for(const [dpi,n] of Object.entries({mdpi:48,hdpi:72,xhdpi:96,xxhdpi:144,xxxhdpi:192}))fs.writeFileSync(path.join(root,`android/app/src/main/res/mipmap-${dpi}/ic_launcher.png`),png(n));


