import {createServer} from 'node:http';
import {readFile} from 'node:fs/promises';
import {resolve, extname, sep} from 'node:path';
const root=resolve(process.cwd());
const types={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.svg':'image/svg+xml','.txt':'text/plain; charset=utf-8'};
createServer(async(req,res)=>{
  const pathname = decodeURIComponent(new URL(req.url,'http://localhost').pathname);
  const file=resolve(root,'.'+(pathname==='/'?'/index.html':pathname));
  if(!file.startsWith(root+sep) || (!file.includes(root+sep+'src'+sep) && !file.includes(root+sep+'assets'+sep) && file!==root+sep+'index.html')) {
    res.writeHead(404);res.end('Not found');return;
  }
  try { const bytes=await readFile(file);res.writeHead(200,{'Content-Type':types[extname(file)]||'application/octet-stream','X-Content-Type-Options':'nosniff'});res.end(bytes); }
  catch {res.writeHead(404);res.end('Not found');}
}).listen(4173,'127.0.0.1',()=>console.log('Helpay is running at http://127.0.0.1:4173'));
