import Foundation
import JavaScriptCore
import Darwin

/// This context only executes the app's bundled parser, never downloaded JavaScript.
enum WebPluginRuntime {
    static func resource(_ name: String, _ ext: String) -> URL {
        Bundle.main.url(forResource: name, withExtension: ext) ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/\(name).\(ext)")
    }
    static func call(_ method: String, _ args: [Any]) throws -> Any {
        guard let ctx = JSContext() else { throw ImportPluginError(message: "无法初始化书源解析器。") }
        ctx.evaluateScript("var FanqieFontMap = " + (try String(contentsOf: resource("fanqie-font-map", "json"), encoding: .utf8)))
        ctx.evaluateScript(try String(contentsOf: resource("web-plugins", "js"), encoding: .utf8))
        let result = ctx.objectForKeyedSubscript("WebPlugins")?.objectForKeyedSubscript(method)?.call(withArguments: args)
        if let error = ctx.exception { throw ImportPluginError(message: error.toString()) }
        guard let value = result?.toObject() else { throw ImportPluginError(message: "书源解析失败。") }
        return value
    }
    static func recommended() throws -> [ImportPluginDefinition] {
        try JSONDecoder().decode([ImportPluginDefinition].self, from: Data(contentsOf: resource("community-plugins", "json")))
    }
    static func manifest(_ data: Data) throws -> ImportPluginDefinition {
        guard data.count <= 262144 else { throw ImportPluginError(message: "插件包不能超过 256 KB。") }
        if data.starts(with: [0x50,0x4b]) {
            // Inspect the central directory before invoking unzip; never extract arbitrary paths.
            func u16(_ n:Int)->Int { Int(data[n]) | Int(data[n+1]) << 8 }
            func u32(_ n:Int)->Int { u16(n) | u16(n+2) << 16 }
            guard data.count >= 22 else { throw ImportPluginError(message: "ZIP 无效。") }
            let end=data.count-22
            guard Array(data[end..<end+4]) == [0x50,0x4b,5,6], u16(end+8)==1, u16(end+10)==1, u16(end+4)==0, u16(end+6)==0 else { throw ImportPluginError(message: "ZIP 必须只包含根目录 manifest.json，不能含注释、目录或其他文件。") }
            let start=u32(end+16)
            guard start >= 0, start+46 <= end, Array(data[start..<start+4]) == [0x50,0x4b,1,2], u16(start+8)&1==0,
                  u32(start+24)<=65536, start+46+u16(start+28)<=end,
                  String(data:data[(start+46)..<(start+46+u16(start+28))],encoding:.utf8)=="manifest.json" else { throw ImportPluginError(message:"ZIP 清单无效、加密或解压后超过 64 KB。") }
            let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".zip")
            try data.write(to:file,options:.atomic); defer { try? FileManager.default.removeItem(at:file) }
            let task=Process(), pipe=Pipe(); task.executableURL=URL(fileURLWithPath:"/usr/bin/unzip"); task.arguments=["-p",file.path,"manifest.json"]; task.standardOutput=pipe; task.standardError=FileHandle.nullDevice; task.standardInput=FileHandle.nullDevice
            try task.run(); var result=Data()
            while let chunk=try pipe.fileHandleForReading.read(upToCount:8192), !chunk.isEmpty { result.append(chunk); if result.count>65536 { task.terminate(); throw ImportPluginError(message:"ZIP 解压超过限制。") } }
            task.waitUntilExit(); guard task.terminationStatus==0 else { throw ImportPluginError(message:"ZIP 校验失败。") }
            return try ImportPluginRegistry.validate(result)
        }
        return try ImportPluginRegistry.validate(data)
    }
}

final class WebDownloadJob {
    private let lock=NSLock()
    private var stopped=false
    private var process: Process?
    private var resolved: [String:(Date,[String])] = [:]
    func cancel() { lock.lock(); stopped=true; if let p=process, p.isRunning { p.terminate() }; lock.unlock() }
    func check() throws { lock.lock(); let value=stopped; lock.unlock(); if value { throw ImportPluginError(message:"任务已取消。") } }
    static func publicIPv4(_ ip:String)->Bool {
        let a=ip.split(separator:".").compactMap{Int($0)}
        guard a.count==4, a.allSatisfy({0...255 ~= $0}) else{return false}
        return !([0,10,127].contains(a[0]) || a[0]>=224 || (a[0]==100 && 64...127 ~= a[1]) || (a[0]==169 && a[1]==254) || (a[0]==172 && 16...31 ~= a[1]) || (a[0]==192 && (a[1]==168 || a[1]==0 || a[1]==2)) || (a[0]==198 && [18,19,51].contains(a[1])) || (a[0]==203 && a[1]==0 && a[2]==113))
    }
    func fetch(_ raw:String, limit:Int=2*1024*1024) throws -> Data {
        try check()
        guard let parts=try WebPluginRuntime.call("address",[raw]) as? [String:Any], let host=parts["host"] as? String else { throw ImportPluginError(message:"地址无效。") }
        if let entry=resolved[host], Date().timeIntervalSince(entry.0)<60 { return try transfer(raw,host:host,ip:entry.1[0],limit:limit) }
        var hints=addrinfo(); hints.ai_family=AF_INET; hints.ai_socktype=SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host,"443",&hints,&result)==0, let first=result else { throw ImportPluginError(message:"域名解析失败。") }
        defer { freeaddrinfo(first) }
        var ips=[String](), cursor: UnsafeMutablePointer<addrinfo>?=first
        while let p=cursor { var buffer=[CChar](repeating:0,count:Int(NI_MAXHOST)); if getnameinfo(p.pointee.ai_addr,p.pointee.ai_addrlen,&buffer,socklen_t(buffer.count),nil,0,NI_NUMERICHOST)==0 { ips.append(String(cString:buffer)) }; cursor=p.pointee.ai_next }
        if !ips.isEmpty, ips.allSatisfy({ $0.hasPrefix("198.18.") || $0.hasPrefix("198.19.") }) {
            // Resolve Fake-IP through a fixed, TLS-verified public resolver. Only the hostname is sent.
            let response = try transfer("https://cloudflare-dns.com/dns-query?name=\(host)&type=A", host:"cloudflare-dns.com", ip:"1.1.1.1", limit:65536, accept:"application/dns-json")
            guard let answer = try JSONSerialization.jsonObject(with:response) as? [String:Any], answer["Status"] as? Int == 0,
                  let questions = answer["Question"] as? [[String:Any]], let question = questions.first?["name"] as? String,
                  question.trimmingCharacters(in:CharacterSet(charactersIn:".")) == host,
                  let records = answer["Answer"] as? [[String:Any]] else {throw ImportPluginError(message:"公共 DNS 未返回有效结果。")}
            ips = records.filter{$0["type"] as? Int == 1}.compactMap{$0["data"] as? String}
        }
        guard !ips.isEmpty, ips.allSatisfy(Self.publicIPv4) else { throw ImportPluginError(message:"DNS 解析到本机、局域网或保留地址，连接已阻止。如果启用了代理 Fake-IP，请为目标域名使用真实公网 DNS 后重试。") }
        resolved[host]=(Date(),ips)
        return try transfer(raw,host:host,ip:ips[0],limit:limit)
    }
    private func transfer(_ raw:String, host:String, ip:String, limit:Int, accept:String="text/html,application/json") throws -> Data {
        try check()
        // Pin the validated IP to the TLS connection, retain hostname verification, ignore proxies/config and reject redirects.
        let task=Process(), pipe=Pipe(); task.executableURL=URL(fileURLWithPath:"/usr/bin/curl")
        task.arguments=["-q","--silent","--show-error","--fail","--noproxy","*","--proto","=https","--max-time","20","--connect-timeout","8","--max-filesize",String(limit),"--resolve","\(host):443:\(ip)","--header","Accept: \(accept)","--user-agent","FishTouchingReader/1.0 (public-page-import)","--write-out","\n%{http_code}",raw]
        task.standardOutput=pipe; task.standardError=FileHandle.nullDevice; task.standardInput=FileHandle.nullDevice
        lock.lock(); if stopped { lock.unlock(); try check(); return Data() }; process=task
        do { try task.run() } catch { process=nil; lock.unlock(); throw error }; lock.unlock()
        defer { lock.lock(); process=nil; lock.unlock() }
        var data=Data()
        while let chunk=try pipe.fileHandleForReading.read(upToCount:16384), !chunk.isEmpty { data.append(chunk); if data.count>limit+4 { task.terminate(); throw ImportPluginError(message:"响应超过大小限制。") }; try check() }
        task.waitUntilExit(); try check()
        if data.suffix(4)==Data("\n202".utf8) { throw ImportPluginError(message:"网站返回 HTTP 202 访问验证页，尚未取得正文；请在官网查看。") }
        guard task.terminationStatus==0, data.suffix(4)==Data("\n200".utf8) else { throw ImportPluginError(message:"网站拒绝访问、发生重定向或请求超时。请使用直接 HTTPS 地址；不会绕过验证。") }
        return data.dropLast(4)
    }
}
