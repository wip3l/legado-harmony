import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

// 礼包字数与说明在“我的权益”页，资格判断在 MembershipGiftRules，会员卡摘要在账号页。
const read = (relative) => fs.readFileSync(new URL(`../entry/src/main/ets/${relative}`, import.meta.url), 'utf8');
const benefitsSource = read('pages/MemberBenefits.ets');
const accountSource = read('pages/AccountCenter.ets');
const rulesSource = read('account/MembershipGiftRules.ets');
function method(source, name) {
  const match = new RegExp(`^  ${name}\\(`, 'm').exec(source);
  assert.ok(match, name);
  return source.slice(match.index, source.indexOf('\n  }', match.index) + 4);
}
const sandbox = vm.createContext({});
vm.runInContext(stripTypeScriptTypes(rulesSource.replace(/^import\s[\s\S]*?;\r?\n/gm, '')
  .replace(/^export /gm, '') + '\nglobalThis.MembershipGiftRules = MembershipGiftRules;', { mode: 'strip' }), sandbox);
vm.runInContext(stripTypeScriptTypes(`globalThis.page = {
  ${[...['giftChars', 'ruleGiftChars', 'giftPeriodText'].map((name) => method(benefitsSource, name)),
    method(accountSource, 'memberCardBenefits')].join(',\n')}
};`, { mode: 'strip' }), sandbox);
const page = sandbox.page;
page.giftIncluded = () => sandbox.MembershipGiftRules.included(page.membership, page.membershipSku);
page.isSuperMember = () => page.membershipSku === 'SUPER_LIFETIME';

for (const [sku, standard, premium] of [
  ['MONTHLY', 0, 0], ['ANNUAL', 5000, 2500], ['LIFETIME', 8000, 4000], ['SUPER_LIFETIME', 12000, 6000]
]) {
  page.membershipSku = sku;
  page.membership = { active: true, restricted: false, claim: null,
    benefits: { standardGiftChars: standard, premiumGiftChars: premium } };
  assert.equal(page.giftIncluded(), standard > 0);
  assert.equal(page.giftChars('STANDARD'), standard);
  assert.equal(page.giftChars('PREMIUM'), premium);
}

// A historical claim remains visible, but does not turn a monthly term into a gift entitlement.
for (const [tier, chars] of [['STANDARD', 2000], ['PREMIUM', 1000]]) {
  page.membershipSku = 'MONTHLY';
  page.membership = { active: true, restricted: false, claim: { tier, chars },
    benefits: { standardGiftChars: 0, premiumGiftChars: 0 } };
  assert.equal(page.giftChars(tier), chars);
  assert.equal(page.giftIncluded(), false, 'old claim must not confer current gift eligibility');
  assert.doesNotMatch(page.memberCardBenefits(), /每月朗读礼包/);
}
page.membershipSku = 'SUPER_LIFETIME';
page.membership = { active: true, restricted: false, claim: { tier: 'STANDARD', chars: 5000 },
  benefits: { standardGiftChars: 12000, premiumGiftChars: 6000 } };
assert.equal(page.giftChars('STANDARD'), 5000, 'upgrading must not rewrite the amount already claimed');
assert.equal(page.giftIncluded(), true);
page.membership.restricted = true;
assert.equal(page.giftIncluded(), false);
page.membership.restricted = false;
page.membership.active = false;
assert.equal(page.giftIncluded(), false);
page.membership.giftCycle = {
  startsAt: Date.parse('2028-02-01T00:00:00+08:00'), endsAt: Date.parse('2028-03-01T00:00:00+08:00')
};
assert.equal(page.giftPeriodText(), '2028年2月1日—29日（北京时间） · 二选一');
console.log('PASS membership gifts: tier amounts, historical claims, upgrades, suspension and Beijing dates');
