// Dreamina CLI only. One submission per artwork; resume existing IDs after interruption.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
const dir = path.resolve('output/neon-harbor');
fs.mkdirSync(dir, { recursive: true });
const stateFile = path.join(dir, 'generation.json');
// Do not let a query and submission overwrite each other's durable task identities.
const lockFile=path.join(dir,'generation.lock');
fs.closeSync(fs.openSync(lockFile,'wx'));
process.on('exit',()=>fs.unlinkSync(lockFile));
const common = '原创复古都市动画插画，1980年代手绘赛璐璐质感，精确墨线、硬边两层阴影、细微胶片颗粒，成熟优雅时装杂志配色，深靛蓝、粉珊瑚、海盐青、暖象牙色。虚构海港都市的书店、唱片与夜班电台世界。非3D非写实，无任何现有动漫角色、制服、猫形标志、盗贼元素。全幅单幅插画，不拼图，无文字、字母、水印、商标。';
const startupPrompt='原创复古都市动画阅读应用启动插画。1980年代手绘赛璐璐动画质感，精确墨线，硬边两层阴影，细微胶片颗粒，成熟优雅时装杂志构图，非3D非写实。虚构海港都市，暮紫天空、粉珊瑚暮光、青碧窗灯，远处轮渡与现代塔楼。画面中上部是三位25至32岁成年女性朋友在屋顶书店露台，三人均完整位于画面中间65%宽度：左侧银灰利落短发、琥珀眼、象牙色短夹克配墨绿阔腿裤、抱着一本书的建筑摄影师；中间赤褐卷发低发髻、棕眼、海盐青西装配奶油衬衣的爵士唱片店主；右侧黑色齐颈波波头、灰蓝眼、陶土橘宽松风衣配深蓝长裤、手拿淡黄色信封的夜班电台编辑。自然交谈，人物不是姐妹，没有制服，没有紧身衣、蒙面、武器、猫形标识或盗贼元素，没有任何现有作品人物。透视优雅，风吹衣角，书页与日常冒险气氛，人物面部与手部清晰。底部四分之一完全留成干净的深靛蓝露台阴影供应用叠字，无人物无道具。海报式单幅插画，全幅画面，无边框，无任何文字、字母、标志、水印。';
const plans = [
  { key:'startup',width:1104,height:2456,prompt:startupPrompt },
  { key:'folder', ratio:'2:3', prompt:'静物近景：海港书店窗台的一叠精装旧书、淡黄色信封、黄铜台灯，背景青碧窗框和雨夜倒影，远处粉色灯光。温暖有人生活的气息，无人物。书本和信件位于中下部，上方保留安静空间。' },
  { key:'icon', ratio:'1:1', prompt:'阅读应用桌面图标，单个简洁粗轮廓的暖象牙色打开的书，书页形成港湾海浪，一枚珊瑚色小圆日落在书页上方，旁边一条海盐青光带。深靛蓝纯色满幅方形背景，不画圆角外边框。符号居中占70%，无微小细节，64像素也清晰，平面赛璐璐设计，不画人物和文字。' },
  { key:'tts_light', ratio:'4:3', prompt:'横向环境插画：清晨电台录音室，窗外淡玫瑰晨光下的海港楼群，室内一台复古唱片机、一本打开的书和耳机。主体全部集中在上方55%，下方45%渐变成干净暖象牙色，没有物件或花纹，供播放按钮叠加。浅色低饱和，明亮通透，无人物。' },
  { key:'tts_dark', ratio:'4:3', prompt:'横向环境插画：午夜电台录音室，窗外深靛蓝海港楼群和柔和珊瑚色与青碧灯光，室内一台复古唱片机、一本打开的书和耳机。主体全部集中在上方55%，下方45%是干净深靛蓝暗部，没有物件或花纹，供播放按钮叠加。柔和低亮度，无人物。' },
  { key:'cover_01', ratio:'2:3', reference:true, prompt:'保持参考图左侧银灰短发成年女性的面容、琥珀眼和象牙短夹克墨绿阔腿裤，单独画她的半身至膝盖肖像。她在雨后的海港天桥举起小型胶片相机，侧身回眸，神情自信温和，风吹短发，远处粉珊瑚晚霞与青碧玻璃。人物占画面55%，只有这一人，构图像一册都市小说封面，不画标题。' },
  { key:'cover_02', ratio:'2:3', reference:true, prompt:'保持参考图中间赤褐卷发低发髻成年女性的脸型、棕眼和海盐青西装奶油衬衣，单独画她在唱片店暖光里从唱片架抽出一张无字唱片的半身肖像。金色窗光、深靛蓝阴影、成熟平静笑容，指尖自然，只有这一人，都市小说封面构图，不画标题。' },
  { key:'cover_03', ratio:'2:3', reference:true, prompt:'保持参考图右侧黑色齐颈波波头成年女性的脸型、灰蓝眼和陶土橘宽松风衣深蓝长裤，单独画她坐在临海夜班电台窗边读淡黄色信件的半身肖像。侧面柔和青光，背景虚焦珊瑚灯光与海港，表情专注，只有这一人，都市小说封面构图，不画标题。' },
  { key:'cover_04', ratio:'2:3', prompt:'雨后午夜的窄街书店外景，深靛蓝建筑和珊瑚橘遮雨篷，青碧无字灯箱，温暖的落地橱窗里展示精装书，路面反射灯光。一把收起的透明雨伞倚门，无人物，没有可读文字，安静的都市悬念感。' },
  { key:'cover_05', ratio:'2:3', prompt:'港湾客轮甲板上的静物场景：木椅、咖啡杯和打开的书。栏杆外是宁静海面与城市远景。粉橘色日落，青绿色海面，蓝紫色阴影，温暖安静的旅行插画。画面没有人物，书页为空白。' },
  { key:'cover_06', ratio:'2:3', prompt:'高处俯瞰夜间电车沿海岸弯道驶过，复古奶油色电车、青碧车窗，珊瑚色街灯在深靛蓝海面映出细长光线，近处建筑窗台有一封淡黄信件和小盆栽，远处城市有高低错落楼群，优美透视，无人物。' }
];
const state = fs.existsSync(stateFile) ? JSON.parse(fs.readFileSync(stateFile,'utf8')) : {themeId:'neon-harbor',themeName:'霓港来信',provider:'dreamina CLI',model:'5.0 (CLI default)',resolution:'2k',items:[]};
const startup=state.items.find(x=>x.key==='startup');
if(startup?.promptIsSummary) {startup.prompt=startupPrompt;delete startup.promptIsSummary;}
const save = ()=>fs.writeFileSync(stateFile,JSON.stringify(state,null,2)+'\n');
save();
const env = {...process.env,HTTP_PROXY:'',HTTPS_PROXY:'',ALL_PROXY:'',http_proxy:'',https_proxy:'',all_proxy:''};
function cli(args) {
  const result = execFileSync('dreamina',args,{env,encoding:'utf8',timeout:120000,windowsHide:true});
  try { return JSON.parse(result); } catch { throw new Error(result.slice(0,1000)); }
}
const mode=process.argv[2];
if(mode==='submit') {
  for(const plan of plans) {
    if(state.items.some(x=>x.key===plan.key)) continue;
    const ref=state.items.find(x=>x.key==='startup');
    if(plan.reference && !ref?.path) continue;
    const prompt=plan.key==='startup'?plan.prompt:common+plan.prompt;
    const args=[plan.reference?'image2image':'text2image','--resolution_type=2k',`--prompt=${prompt}`];
    if(plan.width)args.push(`--width=${plan.width}`,`--height=${plan.height}`);
    else args.push(`--ratio=${plan.ratio}`);
    if(plan.reference) args.push(`--images=${ref.path}`);
    // Record intent before submission. Ambiguous transport failures require history inspection.
    const item={...plan,prompt,command:args[0],status:'submitting'};
    state.items.push(item);save();
    Object.assign(item,cli(args));
    item.status=item.gen_status || 'unknown';
    if(!item.submit_id) {save();throw new Error(JSON.stringify(item));}
    save();console.log(plan.key, item.submit_id,item.gen_status, item.credit_count);
  }
} else if(mode==='query') {
  for(const item of state.items) {
    if(item.path || !item.submit_id || item.gen_status==='fail') continue;
    const target=path.join(dir,item.key);fs.mkdirSync(target,{recursive:true});
    let result;
    try { result=cli(['query_result',`--submit_id=${item.submit_id}`,`--download_dir=${target}`]); }
    catch(error) { console.error(item.key, 'Query interrupted; keep original submit ID:', error.message.slice(0,240)); continue; }
    Object.assign(item,result);
    item.status=item.gen_status;
    const files=fs.readdirSync(target).filter(f=>/\.(png|jpg|jpeg|webp)$/i.test(f));
    if(item.gen_status==='success' && files.length===1) item.path=path.join(target,files[0]);
    save();console.log(item.key,item.gen_status,item.path || result.fail_reason || 'pending');
  }
} else throw new Error('Use submit or query. Generation consumes credits.');
