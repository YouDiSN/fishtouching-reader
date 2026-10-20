'use strict';
const http=require('node:http'),fs=require('node:fs'),path=require('node:path');
const [directory,portFile]=process.argv.slice(2);
const server=http.createServer((req,res)=>{
  const name=decodeURIComponent(new URL(req.url,'http://localhost').pathname.slice(1));
  if(!name || path.basename(name)!==name){res.writeHead(404).end();return;}
  const file=path.join(directory,name);
  if(!fs.existsSync(file)||!fs.statSync(file).isFile()){res.writeHead(404).end();return;}
  res.writeHead(200,{'Content-Length':fs.statSync(file).size});fs.createReadStream(file).pipe(res);
});
server.listen(0,'127.0.0.1',()=>fs.writeFileSync(portFile,String(server.address().port)));
