// Code-native UI companions: original harbor, postcard and radio geometry.
// Illustrations and the launcher icon are generated separately through Dreamina CLI.
import { writeFileSync } from 'node:fs';
const root=new URL('../entry/src/main/resources/base/media/',import.meta.url);
const save=(name,w,h,body)=>writeFileSync(new URL(name+'.svg',root),`<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">${body}</svg>\n`);
for(const mode of ['light','dark']) {
  const ink=mode==='light'?'#9C4058':'#F4A595';
  const teal=mode==='light'?'#387C7A':'#83BDB9';
  const bg=mode==='light'?'#FAF3E9':'#182032';
  // Corner one: a shop awning and a window. Open space towards the reading column.
  save(`reader_decor_neon_harbor_${mode}`,480,480,
    `<g opacity="0.18" fill="none" stroke="${ink}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M14 142V26H154V142M24 34H144V123H24ZM84 34V123M24 76H144M8 143H165"/><path d="M12 27L26 7H142L158 27ZM35 10L29 25M60 10L57 25M85 10V25M110 10L113 25M135 10L141 25"/><path d="M22 123V103H39V123M44 123V95H57V123M62 123V106H75V123"/></g>`+
    `<g opacity="0.16" fill="none" stroke="${teal}" stroke-width="2"><path d="M10 165H115M10 177H73M178 28H219V57H178ZM178 28L198 44 219 28M147 165Q163 156 177 165Q191 175 205 165"/></g>`);
  // Corner two: harbor skyline, ferry and water; not a mirrored copy.
  save(`reader_decor_neon_harbor_trailing_${mode}`,480,480,
    `<g opacity="0.17" fill="none" stroke="${teal}" stroke-width="2.5" stroke-linejoin="round"><path d="M274 422V382H300V422M314 422V349H354V422M362 422V370H393V422M406 422V327H460V422M326 359V401M341 359V401M417 339V410M444 339V410M406 363H460M406 385H460"/><path d="M179 431H270L259 444H193ZM199 431V419H248V431M211 419V408H235V419M158 459Q197 451 236 459T314 459T392 459T470 459"/></g>`+
    `<g opacity="0.18" fill="none" stroke="${ink}" stroke-width="2"><circle cx="365" cy="319" r="17"/><path d="M127 445H162M280 441H343M386 438H463M435 308Q444 296 453 308M225 386Q235 375 245 386"/></g>`);
  save(`reader_bg_neon_harbor_${mode}`,1080,1920,`<rect width="1080" height="1920" fill="${bg}"/>`);
}
save('theme_frame_neon_harbor',450,660,
  '<g fill="none" stroke-width="2"><path d="M8 85V8H104M346 8H442V85M442 575V652H346M104 652H8V575" stroke="#EFA28F"/><path d="M15 77V15H96M354 15H435V77M435 583V645H354M96 645H15V583" stroke="#80B5B2" opacity="0.8"/></g>');
save('theme_logo_neon_harbor',64,64,
  '<rect x="2" y="2" width="60" height="60" rx="14" fill="#182032"/><circle cx="40" cy="21" r="9" fill="#F4A595"/><path d="M10 31Q21 27 32 34Q43 27 54 31V48Q43 45 32 52Q21 45 10 48ZM32 36V49" fill="#FAF3E9"/><path d="M12 54Q22 50 32 54T52 54" fill="none" stroke="#83BDB9" stroke-width="2"/>');
save('regex_frame_harbor_postcard',96,48,
  '<g fill="none" stroke-width="1"><path d="M6 3H90V45H6Z" stroke="#BA777C"/><path d="M9 7H23M29 7H40M56 41H69M75 41H87" stroke="#78A5A3"/></g>');
save('regex_cap_harbor_postcard',24,24,
  '<rect x="2" y="5" width="20" height="14" rx="2" fill="#E9B4A2"/><path d="M3 6L12 13 21 6M3 18L8 13M21 18L16 13" fill="none" stroke="#643244" stroke-width="1.4"/><circle cx="18" cy="7" r="2" fill="#78A5A3"/>');
// Filled paths only: ArkUI fillColor can tint every part without stroke conversion.
const icons={
  bookshelf:'<path d="M3 4H7V18H3ZM9 3H13V18H9ZM15 5L19 4 22 17 18 18ZM2 20H22V22H2Z"/>',
  explore:'<path fill-rule="evenodd" d="M12 1A11 11 0 1 0 12 23A11 11 0 1 0 12 1ZM12 3A9 9 0 1 1 12 21A9 9 0 1 1 12 3ZM17 7L14 14 7 17 10 10ZM13 11L11 11 11 13 13 13Z"/>',
  search:'<path fill-rule="evenodd" d="M10 2A8 8 0 1 0 10 18A8 8 0 1 0 10 2ZM10 4A6 6 0 1 1 10 16A6 6 0 1 1 10 4Z"/><path d="M15 16L17 14 23 20 20 23ZM6 8H14V10H6ZM6 12H12V14H6Z"/>',
  mine:'<path fill-rule="evenodd" d="M12 2A4 4 0 1 0 12 10A4 4 0 1 0 12 2ZM12 4A2 2 0 1 1 12 8A2 2 0 1 1 12 4ZM3 13H21V22H3ZM5 15V20H19V15L12 19ZM7 15L12 17 17 15Z"/>'
};
for(const [tab,body] of Object.entries(icons))save(`ic_theme_neon_harbor_${tab}`,24,24,`<g fill="#000000">${body}</g>`);
console.log('Generated 14 original UI vector resources.');
