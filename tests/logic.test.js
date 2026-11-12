import test from 'node:test';
import assert from 'node:assert/strict';
import {escapeHtml, isValidOfferUrl, validateOffer, calculateSavings, filterOffers, offerExpired} from '../src/logic.js';
test('HTML escaping prevents script and attribute injection',()=>assert.equal(escapeHtml(`<img src=x onerror="x">`),'&lt;img src=x onerror=&quot;x&quot;&gt;'));
test('public source URL must be HTTPS without credentials or private hosts',()=>{
 for(const u of ['javascript:alert(1)','http://example.com','https://user:pass@example.com','https://localhost/','https://127.0.0.1/','https://192.168.1.1'])assert.equal(isValidOfferUrl(u),false,u);
 assert.equal(isValidOfferUrl('https://example.com/offer?a=1'),true);
});
test('calculator applies percentage and flat discounts with caps and min spend',()=>{
 assert.deepEqual(calculateSavings({subtotal:1500,type:'percent',amount:20,cap:250,minimumSpend:500}),{eligible:true,savings:250,finalPrice:1250,missing:0});
 assert.deepEqual(calculateSavings({subtotal:100,type:'flat',amount:200,minimumSpend:0}),{eligible:true,savings:100,finalPrice:0,missing:0});
 assert.deepEqual(calculateSavings({subtotal:490,type:'flat',amount:100,minimumSpend:500}),{eligible:false,savings:0,finalPrice:490,missing:10});
 assert.ok(calculateSavings({subtotal:'NaN',type:'flat',amount:20,minimumSpend:0}).error);
});
test('offer validation disallows private rewards, expired offers and bad discounts',()=>{
 const valid={title:'Public sale',brand:'Example',category:'Shopping',description:'Public sale advertisement',discount_type:'percent',discount_value:10,min_spend:0,expires_at:'2034-12-31T23:59:00Z',source_url:'https://example.com',terms:'One per account',acknowledged:true};
 assert.equal(validateOffer(valid).length,0);
 assert.ok(validateOffer({...valid,acknowledged:false}).length);
 assert.ok(validateOffer({...valid,discount_value:105}).length);
 assert.ok(validateOffer({...valid,expires_at:'2020-01-01T00:00:00Z'}).length);
});
test('search and sort only include published unexpired offers',()=>{
 const fixtures=[
  {id:'t1',brand:'Test A',title:'Food offer',category:'Food',description:'Illustrative test fixture only',status:'published',expires_at:'2034-12-31T23:59:00Z',created_at:'2026-01-01T00:00:00Z'},
  {id:'t2',brand:'Test B',title:'Coding offer',category:'Education',description:'For internal tests only',status:'published',expires_at:'2034-12-31T23:59:00Z',created_at:'2026-01-02T00:00:00Z'},
 ];
 assert.equal(filterOffers(fixtures,{category:'Food'}).length,1);
 assert.equal(filterOffers(fixtures,{query:'coding'}).length,1);
 const mixed=[...fixtures,{...fixtures[0],id:'secret',status:'pending'}];
 assert.equal(filterOffers(mixed).length,fixtures.length);
 assert.equal(offerExpired({...fixtures[0],expires_at:'2020-01-01T00:00:00Z'}),true);
});
