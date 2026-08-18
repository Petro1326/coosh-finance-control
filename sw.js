const CACHE='coosh-finance-v4';
const ASSETS=['./','./index.html','./manifest.webmanifest','./icon.svg'];

self.addEventListener('install',event=>{
  event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(ASSETS)));
  self.skipWaiting();
});

self.addEventListener('activate',event=>{
  event.waitUntil(
    caches.keys()
      .then(keys=>Promise.all(keys.filter(k=>k!==CACHE).map(k=>caches.delete(k))))
      .then(()=>self.clients.claim())
  );
});

self.addEventListener('fetch',event=>{
  if(event.request.method!=='GET') return;
  event.respondWith(
    fetch(event.request).catch(()=>
      caches.match(event.request).then(r=>r||caches.match('./index.html'))
    )
  );
});

self.addEventListener('push',event=>{
  let data={};
  try{ data=event.data ? event.data.json() : {}; }catch(e){
    data={title:'COOSH Finance',body:event.data ? event.data.text() : 'Нове погодження'};
  }

  const title=data.title||'COOSH Finance';
  const options={
    body:data.body||'Новий запис на погодження',
    icon:data.icon||'./icon.svg',
    badge:'./icon.svg',
    tag:data.tag||'coosh-finance-approval',
    renotify:true,
    data:{url:data.url||'./'}
  };

  event.waitUntil(self.registration.showNotification(title,options));
});

self.addEventListener('notificationclick',event=>{
  event.notification.close();
  const target=new URL(event.notification.data?.url||'./',self.location.origin).href;

  event.waitUntil((async()=>{
    const windows=await clients.matchAll({type:'window',includeUncontrolled:true});
    for(const client of windows){
      if('focus' in client){
        await client.navigate(target);
        return client.focus();
      }
    }
    if(clients.openWindow) return clients.openWindow(target);
  })());
});
