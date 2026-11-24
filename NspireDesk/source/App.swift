// NspireDesk — original native Mac interface. GPL-3.0-or-later.
import Cocoa
import UniformTypeIdentifiers

func remoteJoin(_ dir:String,_ name:String)->String { return (dir == "/" ? "" : dir) + "/" + name }
func parentPath(_ path:String)->String { let a=path.split(separator:"/").dropLast(); return a.isEmpty ? "/" : "/"+a.joined(separator:"/") }
func validFolder(_ name:String)->Bool { return !name.isEmpty && name != "." && name != ".." && name.utf8.count <= 100 && !name.contains("/") && !name.contains("\\") && name.rangeOfCharacter(from:.controlCharacters)==nil }
func documentURLs(_ urls:[URL])->Bool { return !urls.isEmpty && urls.allSatisfy{$0.isFileURL && $0.pathExtension.lowercased()=="tns"} }
func label(_ text:String,_ size:CGFloat=13,_ weight:NSFont.Weight = .regular)->NSTextField { let x=NSTextField(wrappingLabelWithString:text);x.font=NSFont.systemFont(ofSize:size,weight:weight);x.textColor = .labelColor;return x }

final class USBService {
    private var process:Process?, input:FileHandle?, output:FileHandle?
    private let receive=DispatchQueue(label:"NspireDesk.receive")
    private var buffer=Data(), serial=0
    private var waiting:[Int:([String:Any])->Void]=[:]
    var progress:(([String:Any])->Void)?
    func start() throws {
        guard process == nil else{return}
        let p=Process();p.executableURL=Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/nspiredesk-usb")
        let to=Pipe(),from=Pipe();p.standardInput=to;p.standardOutput=from;p.standardError=FileHandle.nullDevice
        try p.run();process=p;input=to.fileHandleForWriting;output=from.fileHandleForReading
        from.fileHandleForReading.readabilityHandler={ [weak self] h in
            let bytes=h.availableData
            guard let self=self else{return}
            self.receive.async {
                if bytes.isEmpty {h.readabilityHandler=nil;DispatchQueue.main.async {self.failAll("USB helper stopped. Quit and reopen NspireDesk.")};return}
                self.buffer.append(bytes)
                while let idx=self.buffer.firstIndex(of:10) {
                    let line=self.buffer.prefix(upTo:idx);self.buffer.removeSubrange(...idx)
                    guard let obj=(try? JSONSerialization.jsonObject(with:line)) as? [String:Any] else{continue}
                    DispatchQueue.main.async {
                        if obj["event"] as? String == "progress" {self.progress?(obj)}
                        else if let id=obj["id"] as? Int,let cb=self.waiting.removeValue(forKey:id){cb(obj)}
                    }
                }
            }
        }
    }
    func request(_ args:[String:Any],_ completion:@escaping([String:Any])->Void) {
        do {try start();serial+=1;var req=args;req["id"]=serial;let data=try JSONSerialization.data(withJSONObject:req)+Data([10]);waiting[serial]=completion;try input?.write(contentsOf:data)}
        catch {waiting.removeValue(forKey:serial);completion(["ok":false,"connected":false,"error":error.localizedDescription])}
    }
    private func failAll(_ text:String){let callbacks=waiting.values;waiting.removeAll();for cb in callbacks{cb(["ok":false,"connected":false,"error":text])}}
    func stop(){output?.readabilityHandler=nil;try? input?.close();if process?.isRunning == true {process?.terminate()};process=nil}
}

final class DropZone:NSView {
    var dropped:(([URL])->Void)?, permitted:(()->Bool)?
    private var highlighted=false
    override init(frame:NSRect){super.init(frame:frame);registerForDraggedTypes([.fileURL]);wantsLayer=true}
    required init?(coder:NSCoder){fatalError()}
    override func draw(_ dirtyRect:NSRect){
        (highlighted ? NSColor.controlAccentColor.withAlphaComponent(0.16) : NSColor.controlAccentColor.withAlphaComponent(0.06)).setFill()
        let p=NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:14,yRadius:14);p.fill();NSColor.controlAccentColor.withAlphaComponent(0.6).setStroke();p.lineWidth=1.5;p.setLineDash([6,4],count:2,phase:0);p.stroke()
    }
    private func urls(_ info:NSDraggingInfo)->[URL]{return (info.draggingPasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL]) ?? []}
    override func draggingEntered(_ sender:NSDraggingInfo)->NSDragOperation {highlighted=permitted?() == true && documentURLs(urls(sender));needsDisplay=true;return highlighted ? .copy : []}
    override func draggingExited(_ sender:NSDraggingInfo?){highlighted=false;needsDisplay=true}
    override func performDragOperation(_ sender:NSDraggingInfo)->Bool {defer{highlighted=false;needsDisplay=true};let a=urls(sender);guard permitted?()==true && documentURLs(a) else{return false};dropped?(a);return true}
}

final class App:NSObject,NSApplicationDelegate,NSTableViewDataSource,NSTableViewDelegate,NSFilePromiseProviderDelegate,NSWindowDelegate {
    let service=USBService()
    var window:NSWindow!,table=NSTableView(),devices=NSPopUpButton(),status=label("Plug in your CX II, close other calculator apps, then scan."),detail=label("No calculator connected"),pathLabel=label("My Documents"),log=NSTextView(),preview=NSImageView(),progress=NSProgressIndicator()
    var connectButton:NSButton!, scanButton:NSButton!,refreshButton:NSButton!,upButton:NSButton!,sendButton:NSButton!,receiveButton:NSButton!,folderButton:NSButton!,captureButton:NSButton!,osButton:NSButton!,exitButton:NSButton!
    var entries:[[String:Any]]=[], deviceList:[[String:Any]]=[],info:[String:Any]=[:],path="/",connected=false,busy=false
    var screenshotURL:URL?, batch:[URL]=[], batchTotal=0, batchSent=0
    let promiseQueue=OperationQueue()
    func applicationDidFinishLaunching(_ notification:Notification){buildMenu();buildWindow();service.progress={ [weak self] event in guard let self=self else{return};let done=event["done"] as? Double ?? 0,total=event["total"] as? Double ?? 1;self.progress.isIndeterminate=false;self.progress.doubleValue=total>0 ? 100*done/total : 0;self.status.stringValue="\(event["phase"] as? String ?? "Working") · \(Int(self.progress.doubleValue))%"};window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);updateControls();scan()}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool {window?.deminiaturize(nil);window?.makeKeyAndOrderFront(nil);sender.activate(ignoringOtherApps:true);return true}
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{return true}
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {if busy {alert("Operation in progress","Wait for the USB operation to finish before quitting. During an OS update, keep the cable connected.");return .terminateCancel};return .terminateNow}
    func applicationWillTerminate(_ notification:Notification){service.stop()}
    func windowShouldClose(_ sender:NSWindow)->Bool {if busy {alert("Operation in progress","Wait for the operation to finish before closing this window.");return false};return true}
    func buildMenu(){let menu=NSMenu();let appItem=NSMenuItem();menu.addItem(appItem);let sub=NSMenu();appItem.submenu=sub;let about=NSMenuItem(title:"About NspireDesk",action:#selector(aboutApp),keyEquivalent:"");about.target=self;sub.addItem(about);sub.addItem(.separator());sub.addItem(withTitle:"Quit NspireDesk",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q");let edit=NSMenuItem();menu.addItem(edit);let em=NSMenu(title:"Edit");edit.submenu=em;em.addItem(withTitle:"Copy",action:#selector(NSText.copy(_:)),keyEquivalent:"c");em.addItem(withTitle:"Paste",action:#selector(NSText.paste(_:)),keyEquivalent:"v");em.addItem(withTitle:"Select All",action:#selector(NSText.selectAll(_:)),keyEquivalent:"a");NSApp.mainMenu=menu}
    func button(_ title:String,_ action:Selector)->NSButton{let b=NSButton(title:title,target:self,action:action);b.bezelStyle = .rounded;return b}
    func row(_ views:[NSView],spacing:CGFloat=8)->NSStackView{let s=NSStackView(views:views);s.orientation = .horizontal;s.spacing=spacing;s.alignment = .centerY;return s}
    func column(_ views:[NSView],spacing:CGFloat=12)->NSStackView{let s=NSStackView(views:views);s.orientation = .vertical;s.spacing=spacing;s.alignment = .leading;return s}
    func buildWindow(){
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:1050,height:800),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false);window.title="NspireDesk";window.minSize=NSSize(width:960,height:780);window.center();window.delegate=self
        let root=NSView();window.contentView=root
        let title=label("NspireDesk",28,.bold),tag=label("OFFLINE · USB ONLY",11,.semibold);tag.textColor = .secondaryLabelColor
        let subtitle=label("Your calculator, right here on your Mac.",14);subtitle.textColor = .secondaryLabelColor
        let header=column([row([title,tag],spacing:18),subtitle],spacing:3)
        scanButton=button("Scan USB",#selector(scan));connectButton=button("Connect",#selector(connect));devices.widthAnchor.constraint(greaterThanOrEqualToConstant:290).isActive=true
        let conn=row([devices,scanButton,connectButton]);detail.textColor = .secondaryLabelColor
        upButton=button("Up",#selector(up));refreshButton=button("Refresh",#selector(refresh));folderButton=button("New Folder",#selector(newFolder));sendButton=button("Send Files…",#selector(chooseSend));receiveButton=button("Save to Mac…",#selector(downloadSelected))
        let toolbar=row([upButton,refreshButton,folderButton,sendButton,receiveButton]);pathLabel.font = .monospacedSystemFont(ofSize:12,weight:.medium)
        table.addTableColumn(NSTableColumn(identifier:NSUserInterfaceItemIdentifier("name")));table.tableColumns[0].title="Calculator files";table.tableColumns[0].width=350
        let size=NSTableColumn(identifier:NSUserInterfaceItemIdentifier("size"));size.title="Size";size.width=90;table.addTableColumn(size)
        table.dataSource=self;table.delegate=self;table.target=self;table.doubleAction=#selector(openRow);table.rowHeight=30;table.usesAlternatingRowBackgroundColors=true;table.allowsMultipleSelection=false;table.setDraggingSourceOperationMask(.copy,forLocal:false)
        let scroll=NSScrollView();scroll.documentView=table;scroll.hasVerticalScroller=true;scroll.borderType = .bezelBorder
        let drop=DropZone();let dt=column([label("Drop .tns files here",17,.semibold),label("Send to the folder shown above. Drag a file out to save it to Finder.",11)],spacing:5);dt.translatesAutoresizingMaskIntoConstraints=false;drop.addSubview(dt);NSLayoutConstraint.activate([dt.centerXAnchor.constraint(equalTo:drop.centerXAnchor),dt.centerYAnchor.constraint(equalTo:drop.centerYAnchor),dt.widthAnchor.constraint(lessThanOrEqualTo:drop.widthAnchor,constant:-24)]);drop.heightAnchor.constraint(equalToConstant:82).isActive=true;drop.permitted={ [weak self] in self?.connected == true && self?.busy == false };drop.dropped={ [weak self] urls in self?.startBatch(urls) }
        let left=column([toolbar,pathLabel,scroll,drop],spacing:10)
        for v in [toolbar,pathLabel,scroll,drop]{v.widthAnchor.constraint(equalTo:left.widthAnchor).isActive=true}
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:225).isActive=true
        captureButton=button("Capture Screen…",#selector(capture));osButton=button("Update OS…",#selector(updateOS));exitButton=button("Exit Press-to-Test…",#selector(exitTest))
        preview.imageScaling = .scaleProportionallyUpOrDown;preview.wantsLayer=true;preview.layer?.backgroundColor=NSColor.controlBackgroundColor.cgColor;preview.widthAnchor.constraint(equalToConstant:240).isActive=true;preview.heightAnchor.constraint(equalToConstant:180).isActive=true
        let previewHint=label("Capture the calculator screen as a PNG. No Mac screen-recording permission needed.",12);previewHint.textColor = .secondaryLabelColor
        let firmwareHint=label("Install a previously downloaded TI OS image. Review the target model before starting.",12);firmwareHint.textColor = .secondaryLabelColor
        let exitHint=label("Send the standard exit document. The handheld restarts and clears work created in test mode.",12);exitHint.textColor = .secondaryLabelColor
        let screenPane=column([preview,captureButton,previewHint],spacing:12)
        let toolsPane=column([label("Calculator tools",17,.semibold),osButton,firmwareHint,exitButton,exitHint],spacing:14)
        let right=NSTabView()
        for (title,pane) in [("Screen",screenPane),("Tools",toolsPane)] {
            let item=NSTabViewItem(identifier:title);item.label=title
            let wrapper=NSView();pane.translatesAutoresizingMaskIntoConstraints=false;wrapper.addSubview(pane)
            NSLayoutConstraint.activate([pane.leadingAnchor.constraint(equalTo:wrapper.leadingAnchor,constant:12),pane.trailingAnchor.constraint(equalTo:wrapper.trailingAnchor,constant:-12),pane.topAnchor.constraint(equalTo:wrapper.topAnchor,constant:16),pane.bottomAnchor.constraint(lessThanOrEqualTo:wrapper.bottomAnchor,constant:-12)])
            item.view=wrapper;right.addTabViewItem(item)
        }
        right.widthAnchor.constraint(equalToConstant:280).isActive=true
        for v in [previewHint,firmwareHint,exitHint]{v.widthAnchor.constraint(equalToConstant:240).isActive=true}
        let body=row([left,right],spacing:24);right.heightAnchor.constraint(equalTo:left.heightAnchor).isActive=true;body.alignment = .top;left.setContentHuggingPriority(.defaultLow,for:.horizontal)
        log.isEditable=false;log.font = .monospacedSystemFont(ofSize:11,weight:.regular);log.backgroundColor = .textBackgroundColor
        let logs=NSScrollView();logs.documentView=log;logs.hasVerticalScroller=true;logs.heightAnchor.constraint(equalToConstant:75).isActive=true
        progress.minValue=0;progress.maxValue=100;progress.isIndeterminate=false;progress.style = .bar;progress.heightAnchor.constraint(equalToConstant:4).isActive=true
        let stack=column([header,conn,detail,body,progress,status,logs],spacing:12);stack.translatesAutoresizingMaskIntoConstraints=false;root.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:24),stack.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-24),stack.topAnchor.constraint(equalTo:root.topAnchor,constant:22),stack.bottomAnchor.constraint(equalTo:root.bottomAnchor,constant:-20)])
        for v in [header,conn,detail,body,progress,status,logs]{v.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true}
        logLine("Local build · hardware validation pending. No accounts, websites, or network service required.")
    }
    func logLine(_ text:String){let date=DateFormatter();date.dateFormat="HH:mm:ss";log.textStorage?.append(NSAttributedString(string:"[\(date.string(from:Date()))] \(text)\n"));log.scrollToEndOfDocument(nil)}
    func updateControls(){scanButton.isEnabled = !busy && !connected;devices.isEnabled = !busy && !connected;connectButton.isEnabled = !busy && (connected || !deviceList.isEmpty);connectButton.title=connected ? "Disconnect" : "Connect";for b in [refreshButton,upButton,sendButton,folderButton,captureButton,osButton,exitButton]{b?.isEnabled = connected && !busy};receiveButton.isEnabled=connected && !busy && selectedFile() != nil;table.isEnabled = !busy;upButton.isEnabled=connected && !busy && path != "/"}
    func selectedFile()->[String:Any]?{let i=table.selectedRow;guard i>=0 && i<entries.count,entries[i]["folder"] as? Bool != true else{return nil};return entries[i]}
    func alert(_ title:String,_ text:String){let a=NSAlert();a.messageText=title;a.informativeText=text;a.addButton(withTitle:"OK");a.runModal()}
    func confirm(_ title:String,_ text:String,_ yes:String)->Bool {let a=NSAlert();a.messageText=title;a.informativeText=text;a.alertStyle = .warning;a.addButton(withTitle:"Cancel");a.addButton(withTitle:yes);return a.runModal() == .alertSecondButtonReturn}
    func request(_ args:[String:Any],message:String,completion:(([String:Any])->Void)?=nil){
        guard !busy else{alert("Please wait","Finish the current operation first.");return};busy=true;status.stringValue=message;progress.isIndeterminate=true;progress.startAnimation(nil);updateControls()
        service.request(args){ [weak self] response in guard let self=self else{return};self.busy=false;self.connected=response["connected"] as? Bool ?? false;self.progress.stopAnimation(nil);self.progress.isIndeterminate=false
            if response["ok"] as? Bool == true {let data=response["data"] as? [String:Any] ?? [:];let msg=data["message"] as? String ?? "Ready";self.status.stringValue=msg;self.progress.doubleValue=100;if msg != "Ready"{self.logLine(msg)};self.updateControls();completion?(data)}
            else {let error=response["error"] as? String ?? "Unknown USB error";self.status.stringValue="Operation stopped";self.logLine(error);self.batch=[];self.updateControls();self.alert("Could not finish",error+"\n\nNspireDesk 0.1.3 · If this persists, copy the full message from the activity log so the failed connection stage can be identified.")}
            if !self.connected {self.info=[:];self.detail.stringValue="Not connected";self.entries=[];self.table.reloadData()};self.updateControls()
        }
    }
    @objc func scan(){request(["op":"scan"],message:"Looking for CX II calculators…"){data in self.deviceList=data["devices"] as? [[String:Any]] ?? [];self.devices.removeAllItems();for d in self.deviceList{self.devices.addItem(withTitle:d["label"] as? String ?? "CX II")};if self.deviceList.isEmpty{self.devices.addItem(withTitle:"No CX II found");self.status.stringValue="No calculator found. Check power and the USB data cable."};self.updateControls()}}
    @objc func connect(){if connected{request(["op":"disconnect"],message:"Disconnecting…");return};let i=devices.indexOfSelectedItem;guard i>=0 && i<deviceList.count else{return};let d=deviceList[i];request(["op":"connect","bus":d["bus"]!,"address":d["address"]!],message:"Connecting…"){data in self.info=data;let v=data["version"] as? [String:Any] ?? [:];let version=["major","minor","patch","build"].map{String(describing:v[$0] ?? "?")}.joined(separator:".");let name=data["name"] as? String ?? "TI-Nspire CX II";let free=data["free_storage"] as? Int64 ?? 0;self.detail.stringValue="\(name) · OS \(version) · \(ByteCountFormatter.string(fromByteCount:free,countStyle:.file)) free";self.logLine("Connected to \(name)");self.path="/";self.refresh()}}
    @objc func refresh(){let requested=path;request(["op":"list","path":requested],message:"Reading calculator files…"){data in self.path=data["path"] as? String ?? "/";self.pathLabel.stringValue="My Documents"+(self.path == "/" ? "" : self.path);self.entries=(data["entries"] as? [[String:Any]] ?? []).sorted{a,b in if (a["folder"] as? Bool ?? false) != (b["folder"] as? Bool ?? false){return a["folder"] as? Bool ?? false};return (a["name"] as? String ?? "").localizedStandardCompare(b["name"] as? String ?? "") == .orderedAscending};self.table.reloadData();self.status.stringValue=self.path == "/" ? "Open or create a folder to send documents." : "\(self.entries.count) items · drop .tns files to send";self.updateControls()}}
    @objc func up(){path=parentPath(path);refresh()}
    @objc func openRow(){let i=table.clickedRow;guard !busy && i>=0 && i<entries.count else{return};if entries[i]["folder"] as? Bool == true {path=remoteJoin(path,entries[i]["name"] as? String ?? "");refresh()}else{downloadSelected()}}
    @objc func newFolder(){let a=NSAlert();a.messageText="Create a calculator folder";let field=NSTextField(frame:NSRect(x:0,y:0,width:260,height:24));a.accessoryView=field;a.addButton(withTitle:"Cancel");a.addButton(withTitle:"Create");a.window.initialFirstResponder=field;guard a.runModal() == .alertSecondButtonReturn else{return};let name=field.stringValue.trimmingCharacters(in:.whitespaces);guard validFolder(name) else{alert("Invalid name","Use a short folder name without slashes.");return};request(["op":"mkdir","path":remoteJoin(path,name)],message:"Creating folder…"){_ in self.refresh()}}
    @objc func chooseSend(){let p=NSOpenPanel();p.allowedContentTypes=[UTType(filenameExtension:"tns") ?? .data];p.allowsMultipleSelection=true;p.canChooseDirectories=false;p.prompt="Send";if p.runModal() == .OK{startBatch(p.urls)}}
    func startBatch(_ urls:[URL]){guard connected && !busy else{return};guard path != "/" else{alert("Open a folder first","Double-click a calculator folder, or create a new folder, then drop your documents there.");return};guard documentURLs(urls) else{alert("Choose TNS documents","Drop .tns files here. Use Update OS for an OS image.");return};batch=urls;batchTotal=urls.count;batchSent=0;sendNext()}
    func sendNext(){guard !batch.isEmpty else{logLine("Transfer batch complete: \(batchSent) of \(batchTotal) sent and verified.");refresh();return};let u=batch.removeFirst();let collision=entries.contains{($0["name"] as? String)==u.lastPathComponent};var replace=false;if collision{replace=confirm("Replace \(u.lastPathComponent)?","A file with this name is already in \(path). Replacing it cannot be undone by this app.","Replace");if !replace{logLine("Skipped \(u.lastPathComponent)");sendNext();return}};request(["op":"upload","path":path,"local":u.path,"replace":replace],message:"Sending \(u.lastPathComponent)…"){_ in self.batchSent+=1;if !collision{self.entries.append(["name":u.lastPathComponent,"folder":false])};self.sendNext()}}
    @objc func downloadSelected(){guard let file=selectedFile(),let name=file["name"] as? String else{return};let p=NSSavePanel();p.nameFieldStringValue=name;p.prompt="Save";if p.runModal() == .OK,let url=p.url{if FileManager.default.fileExists(atPath:url.path){alert("Choose a new filename","This app preserves existing local files. Choose an unused filename.");return};request(["op":"download","path":remoteJoin(path,name),"local":url.path],message:"Receiving \(name)…"){_ in NSWorkspace.shared.activateFileViewerSelecting([url])}}}
    @objc func capture(){let p=NSSavePanel();p.allowedContentTypes=[.png];let f=DateFormatter();f.dateFormat="yyyy-MM-dd-HHmmss";p.nameFieldStringValue="Nspire-\(f.string(from:Date())).png";if p.runModal() == .OK,let url=p.url{request(["op":"screenshot","local":url.path],message:"Capturing calculator screen…"){_ in self.preview.image=NSImage(contentsOf:url);self.screenshotURL=url}}}
    @objc func updateOS(){guard let ext=info["os_extension"] as? String else{return};let p=NSOpenPanel();p.allowedContentTypes=[UTType(filenameExtension:ext.trimmingCharacters(in:CharacterSet(charactersIn:"."))) ?? .data];p.allowsMultipleSelection=false;p.message="Choose the official TI OS image you previously downloaded for this calculator.";guard p.runModal() == .OK,let url=p.url else{return};let model=info["name"] as? String ?? "CX II";let size=(try? url.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0;guard confirm("Install OS on \(model)?","File: \(url.lastPathComponent)\nSize: \(ByteCountFormatter.string(fromByteCount:Int64(size),countStyle:.file))\nRequired extension: \(ext)\n\nUse an official TI image for this model. Back up documents first. Keep the calculator charged and the USB cable connected throughout transfer and installation. This build has not yet been tested on your hardware.","Install OS") else{return};request(["op":"os","local":url.path,"confirmed":true,"deviceID":info["id"] as? String ?? ""],message:"Installing OS — do not unplug…")}
    @objc func exitTest(){guard confirm("Exit Press-to-Test?","This sends the standard Exit Test Mode document to the selected calculator. The handheld may restart and permanently delete work created while it was in test mode. Previously stored documents become accessible again.\n\nAfterward, check the handheld to confirm test mode is off.","Send exit request") else{return};request(["op":"exit_test","confirmed":true],message:"Sending exit request…")}
    @objc func aboutApp(){alert("NspireDesk 0.1.3 — local preview","An independent offline USB companion for TI-Nspire CX II. No TI account or internet connection required.\n\nIncludes file transfers, PNG capture, local OS installation, and the standard exit-test document workflow. Hardware validation is still pending. Not affiliated with Texas Instruments.\n\nSource and third-party notices are included alongside the app.")}
    func numberOfRows(in tableView:NSTableView)->Int{return entries.count}
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView?{let e=entries[row];if tableColumn?.identifier.rawValue=="size"{return label(e["folder"] as? Bool == true ? "Folder" : ByteCountFormatter.string(fromByteCount:(e["size"] as? Int64 ?? 0),countStyle:.file),12)};return label((e["folder"] as? Bool == true ? "📁  " : "📄  ")+(e["name"] as? String ?? ""))}
    func tableViewSelectionDidChange(_ notification:Notification){updateControls()}
    func tableView(_ tableView:NSTableView,pasteboardWriterForRow row:Int)->NSPasteboardWriting?{guard connected && !busy && entries[row]["folder"] as? Bool != true,let name=entries[row]["name"] as? String else{return nil};let p=NSFilePromiseProvider(fileType:"public.data",delegate:self);p.userInfo=["name":name,"path":remoteJoin(path,name)];return p}
    func filePromiseProvider(_ provider:NSFilePromiseProvider,fileNameForType fileType:String)->String{return (provider.userInfo as? [String:String])?["name"] ?? "Document.tns"}
    func operationQueue(for provider:NSFilePromiseProvider)->OperationQueue{return promiseQueue}
    func filePromiseProvider(_ provider:NSFilePromiseProvider,writePromiseTo url:URL,completionHandler:@escaping(Error?)->Void){
        guard let data=provider.userInfo as? [String:String],let remote=data["path"] else{completionHandler(NSError(domain:"NspireDesk",code:1,userInfo:[NSLocalizedDescriptionKey:"Missing source file"]));return}
        DispatchQueue.main.async {guard self.connected && !self.busy else{completionHandler(NSError(domain:"NspireDesk",code:2,userInfo:[NSLocalizedDescriptionKey:"Calculator is busy or disconnected"]));return};self.busy=true;self.status.stringValue="Receiving file into Finder…";self.updateControls();self.service.request(["op":"download","path":remote,"local":url.path]){r in self.busy=false;self.connected=r["connected"] as? Bool ?? false;if r["ok"] as? Bool == true{self.status.stringValue="Saved to Finder";self.logLine("Saved \(url.lastPathComponent)");completionHandler(nil)}else{let msg=r["error"] as? String ?? "Transfer failed";self.status.stringValue=msg;self.logLine(msg);completionHandler(NSError(domain:"NspireDesk",code:3,userInfo:[NSLocalizedDescriptionKey:msg]))};self.updateControls()}}
    }
}

if CommandLine.arguments.contains("--self-test") {
    precondition(parentPath("/folder/nested")=="/folder")
    precondition(parentPath("/folder")=="/")
    precondition(remoteJoin("/","file.tns")=="/file.tns")
    precondition(validFolder("My Lessons") && !validFolder("../bad") && !validFolder(".."))
    precondition(documentURLs([URL(fileURLWithPath:"/tmp/test.tns")]))
    precondition(!documentURLs([URL(fileURLWithPath:"/tmp/os.tco2")]))
    print("PASS: Mac path and drop validation checks")
} else {
    let app=NSApplication.shared;app.setActivationPolicy(.regular);let delegate=App();app.delegate=delegate
    if let flag=CommandLine.arguments.firstIndex(of:"--ui-check"),CommandLine.arguments.count>flag+1 {
        delegate.buildMenu();delegate.buildWindow();delegate.updateControls()
        let view=delegate.window.contentView!;view.layoutSubtreeIfNeeded()
        let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds)!;view.cacheDisplay(in:view.bounds,to:rep)
        try! rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[flag+1]))
        print("PASS: Native window rendered at \(view.bounds.width) × \(view.bounds.height)")
    } else {app.run()}
}
