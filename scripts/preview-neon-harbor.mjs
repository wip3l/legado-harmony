// A review board using the shipping assets/tokens. This is a design preview, not a device screenshot.
import fs from 'node:fs';
import {createRequire} from 'node:module';
import {loadObsidianReader} from './lib/obsidian-reader-fixture.mjs';
const require=createRequire(import.meta.url),sharp=require('../server/node_modules/sharp');
const {BuiltinThemeRegistry:registry}=loadObsidianReader();
const theme=registry.findById('neon-harbor');
const root='entry/src/main/resources/base/media/';
const esc=x=>String(x).replaceAll('&','&amp;').replaceAll('<','&lt;');
const text=(x,y,body,size=20,color='#F5EADF',weight=400)=>`<text x="${x}" y="${y}" font-size="${size}" font-weight="${weight}" fill="${color}" font-family="Microsoft YaHei, sans-serif">${esc(body)}</text>`;
const rect=(x,y,w,h,fill,rx=0)=>`<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${rx}" fill="${fill}"/>`;
const image=(file,x,y,w,h)=>`<image x="${x}" y="${y}" width="${w}" height="${h}" preserveAspectRatio="xMidYMid slice" href="data:${file.endsWith('.svg')?'image/svg+xml':file.endsWith('.png')?'image/png':'image/jpeg'};base64,${fs.readFileSync(file).toString('base64')}"/>`;
const art=(name,x,y,w,h)=>image(root+name,x,y,w,h);
const phone=(x,body)=>`<g transform="translate(${x} 230)">${rect(-7,-7,354,770,'#374059',35)}<g clip-path="url(#phone)">${body}</g></g>`;
const status=(color)=>text(24,31,'9:41',14,color,600)+text(252,31,'● ▰',14,color);
const footer=(dark)=>{
  const c=dark?theme.dark.colors:theme.light.colors;
  let s=rect(14,678,312,60,c.cardColor,20);
  ['bookshelf','explore','search','mine'].forEach((tab,i)=>{
    s+=art(`ic_theme_neon_harbor_${tab}.svg`,40+i*75,689,21,21)+text(37+i*75,727,['书架','发现','搜索','我的'][i],12,c.subTextColor);
  });
  return s;
};
let body=rect(0,0,1800,1260,'#101726');
body+=text(60,64,'QINGYE  /  ORIGINAL THEME COLLECTION',17,'#83BDB9',600);
body+=text(60,133,'霓港来信',57,'#FAF3E9',600);
body+=text(365,130,'NEON HARBOR',28,'#F4A595',400);
body+=text(62,178,'海风翻动书页，电台捎来晚安。',23,'#B9ACB8');
body+=text(1265,80,'RETRO ANIMATION · CITY LETTERS',17,'#83BDB9');
body+=text(1265,118,'原创角色 / 即梦插画 / 浅深双模式',19,'#B9ACB8');
// Startup: production art reserves its lower fifth for the app mark.
let startup=art('theme_startup_neon_harbor.jpg',0,0,340,756);
startup+=status('#F7F1EA')+text(29,663,'轻页',35,'#FFF3E9',600)+text(30,697,'把今晚，留给下一页。',17,'#E5DFD8');
body+=phone(70,startup);
// Light bookshelf: six exact shipped covers, no added character art in the controls.
const c=theme.light.colors;
let shelf=rect(0,0,340,756,c.pageColor)+status(c.primaryTextColor)+text(23,87,'书架',31,c.primaryTextColor,600)+text(252,84,'＋  ⋮',22,c.accentColor);
shelf+=text(23,120,'全部书籍    正在读    已读完',15,c.subTextColor);
shelf+=rect(20,141,300,72,c.cardColor,10)+text(35,168,'继续阅读',12,c.accentColor,600)+text(35,195,'海风来信  ·  第十二章',17,c.primaryTextColor);
const titles=['沿岸取景','唱片里的夏天','晚安电台','雨巷书店','海上慢信','末班电车'];
for(let i=0;i<6;i++){
  const x=20+(i%3)*105,y=234+Math.floor(i/3)*205;
  shelf+=art(`theme_cover_neon_harbor_0${i+1}.jpg`,x,y,90,132)+art('theme_frame_neon_harbor.svg',x,y,90,132);
  shelf+=text(x,y+155,titles[i],13,c.primaryTextColor,500)+text(x,y+176,'阅读至 12%',11,c.subTextColor);
}
shelf+=footer(false);body+=phone(510,shelf);
// Dark reader: exact background and two independently drawn ornaments.
const r=theme.dark.reader;
let reader=rect(0,0,340,756,r.backgroundColor)+art('reader_decor_neon_harbor_dark.svg',10,44,122,122)+art('reader_decor_neon_harbor_trailing_dark.svg',208,594,122,122)+status(r.subTextColor);
reader+=text(26,78,'海风来信',13,r.subTextColor)+text(26,132,'第十二章  午夜的频率',22,r.textColor,600);
const lines=['港湾的灯一盏盏亮了起来。','她推开书店的门，唱片恰好','转到第二面。窗外，最后一','班电车沿着海岸缓缓驶过。','','信封里没有地址，只有一句','熟悉的问候。她把书签夹回','原处，抬头看向窗边的朋友。'];
lines.forEach((line,i)=>reader+=text(26,185+i*37,line,20,r.textColor));
reader+=rect(26,506,279,38,theme.dark.regexEmphasis.emphasisColor,5)+text(39,532,'“明天，一起去看海吧。”',19,theme.dark.regexEmphasis.emphasisTextColor);
reader+=art('regex_cap_harbor_postcard.svg',279,493,24,24);
reader+=text(26,591,'电台里传来轻柔的晚安。',20,r.textColor)+text(26,628,'她微笑着，翻开了下一页。',20,r.textColor);
reader+=text(26,721,'12 / 86',12,r.subTextColor)+text(255,721,'23:41',12,r.subTextColor);body+=phone(950,reader);
// Audio panel: same artwork and 50% fade arrangement as TtsPanelThemeBackground.
let player=rect(0,0,340,756,c.pageColor)+art('tts_panel_neon_harbor_light.jpg',0,0,340,246)+`<rect x="0" y="123" width="340" height="123" fill="url(#audioFade)"/>`+status(c.primaryTextColor);
player+=text(25,286,'正在朗读',13,c.accentColor,600)+text(25,328,'海风来信',29,c.primaryTextColor,600)+text(25,363,'第十二章 · 午夜的频率',16,c.subTextColor);
player+=rect(25,412,290,70,c.cardColor,10)+text(41,441,'“电台里传来轻柔的晚安。”',17,c.primaryTextColor)+text(41,466,'温柔女声  ·  1.0×',13,c.subTextColor);
player+=rect(27,523,286,3,'#D8CBCB',2)+rect(27,523,112,3,c.accentColor,2)+text(26,549,'08:24',12,c.subTextColor)+text(276,549,'21:36',12,c.subTextColor);
player+=`<circle cx="170" cy="610" r="35" fill="${c.buttonColor}"/>`+rect(158,596,8,28,'#FFFFFF',2)+rect(174,596,8,28,'#FFFFFF',2)+text(60,618,'‹‹',31,c.accentColor)+text(251,618,'››',31,c.accentColor);
player+=text(35,697,'目录',14,c.subTextColor)+text(141,697,'定时关闭',14,c.subTextColor)+text(273,697,'语速',14,c.subTextColor);body+=phone(1390,player);
['01  启动 · 都市友人','02  书架 · 象牙晨光','03  阅读 · 靛蓝夜航','04  听书 · 晨间电台'].forEach((label,i)=>body+=text(70+i*440,1041,label,20,'#F5EADF',500));
body+=`<path d="M60 1082H1740" stroke="#374059"/>`;
['#182032','#F4A595','#83BDB9','#FAF3E9','#9C4058'].forEach((color,i)=>{body+=rect(62+i*135,1110,46,46,color,10)+text(62+i*135,1182,color,15,'#B9ACB8');});
body+=text(800,1136,'11 张即梦插画  ·  6 张独立书封  ·  14 项矢量部件',22,'#F5EADF');
body+=text(800,1175,'设计预览，采用项目实际素材与主题配色；非真机截图。',17,'#B9ACB8');
const svg=`<svg xmlns="http://www.w3.org/2000/svg" width="1800" height="1260" viewBox="0 0 1800 1260"><defs><clipPath id="phone"><rect width="340" height="756" rx="29"/></clipPath><linearGradient id="audioFade" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#F7F1EA" stop-opacity="0"/><stop offset="1" stop-color="#F7F1EA"/></linearGradient></defs>${body}</svg>`;
fs.writeFileSync('output/neon-harbor/design-preview.svg',svg);
await sharp(Buffer.from(svg)).png().toFile('output/neon-harbor/design-preview.png');
console.log('Created output/neon-harbor/design-preview.png');
