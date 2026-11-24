import Cocoa
import UniformTypeIdentifiers

class FlippedView:NSView {override var isFlipped:Bool{true}}
final class ImportArea:FlippedView {
 var receive:(([URL])->Void)?,allowed:(()->Bool)?
 override init(frame:NSRect){super.init(frame:frame);registerForDraggedTypes([.fileURL])}
 required init?(coder:NSCoder){fatalError()}
 func urls(_ sender:NSDraggingInfo)->[URL]{(sender.draggingPasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL]) ?? []}
 override func draggingEntered(_ sender:NSDraggingInfo)->NSDragOperation{allowed?()==true && !urls(sender).isEmpty ? .copy:[]}
 override func performDragOperation(_ sender:NSDraggingInfo)->Bool{guard allowed?()==true else{return false};receive?(urls(sender));return true}
}
func textLabel(_ text:String,_ size:CGFloat=13,_ bold:Bool=false)->NSTextField {let f=NSTextField(wrappingLabelWithString:text);f.font = .systemFont(ofSize:size,weight:bold ? .semibold:.regular);return f}
final class CalculatorPreview:NSView {
 var page=NotePage(title:"",text:""),fontSize=11
 override func draw(_ rect:NSRect){
  NSColor.windowBackgroundColor.setFill();bounds.fill()
  let width:CGFloat=320,height:CGFloat=240,x=(bounds.width-width)/2,y=max(40,(bounds.height-height)/2)
  let box=NSRect(x:x,y:y,width:width,height:height)
  NSColor(calibratedWhite:0.97,alpha:1).setFill();box.fill()
  NSColor(calibratedRed:0.08,green:0.19,blue:0.27,alpha:1).setFill();NSRect(x:x,y:y+height-30,width:width,height:30).fill()
  (page.title as NSString).draw(in:NSRect(x:x+8,y:y+height-26,width:width-16,height:23),withAttributes:[.font:NSFont.systemFont(ofSize:12,weight:.semibold),.foregroundColor:NSColor.white])
  let content=page.kind == .notes ? page.text : "Code page\n\nScripts are packaged for the calculator. They are not executed in this preview."
  NSGraphicsContext.saveGraphicsState();NSBezierPath(rect:NSRect(x:x+10,y:y+28,width:300,height:175)).addClip()
  (content as NSString).draw(in:NSRect(x:x+10,y:y+28,width:300,height:175),withAttributes:[.font:NSFont.systemFont(ofSize:CGFloat(fontSize)),.foregroundColor:NSColor.black]);NSGraphicsContext.restoreGraphicsState()
  ("Up/Down scroll · Left/Right jump" as NSString).draw(at:NSPoint(x:x+9,y:y+8),withAttributes:[.font:NSFont.systemFont(ofSize:10),.foregroundColor:NSColor.darkGray])
  ("Approximate first-screen preview · not an emulator" as NSString).draw(at:NSPoint(x:max(5,x-7),y:y-28),withAttributes:[.font:NSFont.systemFont(ofSize:12),.foregroundColor:NSColor.secondaryLabelColor])
 }
}
final class StudioApp:NSObject,NSApplicationDelegate,NSWindowDelegate,NSTableViewDataSource,NSTableViewDelegate,NSTextViewDelegate,NSTextFieldDelegate {
 var window:NSWindow!,project=Project(),projectURL:URL?,active=0,loading=false,dirty=false,busy=false
 var table=NSTableView(),editor=NSTextView(),docTitle=NSTextField(),pageTitle=NSTextField(),kind=NSPopUpButton(),font=NSPopUpButton(),template=NSPopUpButton()
 var status=textLabel("Import a PDF or document, review its text, then export a TNS."),origin=textLabel(""),preview=CalculatorPreview(),buttons:[NSButton]=[]
 var recoveryTimer:Timer?
 var pendingOpen:URL?
 var recoveryURL:URL {FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("TNSStudio/Recovery.tnsproject")}
 func applicationDidFinishLaunching(_ note:Notification){buildMenu();buildWindow();showPage();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);restoreRecovery();if let url=pendingOpen{pendingOpen=nil;openProject(url)}}
 func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool {window.makeKeyAndOrderFront(nil);window.deminiaturize(nil);sender.activate(ignoringOtherApps:true);return true}
 func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{true}
 func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply{canLeave() ? .terminateNow:.terminateCancel}
 func windowShouldClose(_ sender:NSWindow)->Bool{canLeave()}
 func application(_ sender:NSApplication,openFile filename:String)->Bool{guard window != nil else{pendingOpen=URL(fileURLWithPath:filename);return true};openProject(URL(fileURLWithPath:filename));return true}
 func alert(_ title:String,_ message:String){let a=NSAlert();a.messageText=title;a.informativeText=message;a.runModal()}
 func buildMenu(){
  let menu=NSMenu(),appItem=NSMenuItem();menu.addItem(appItem);let appMenu=NSMenu();appItem.submenu=appMenu
  let about=NSMenuItem(title:"About TNS Studio",action:#selector(about),keyEquivalent:"");about.target=self;appMenu.addItem(about);appMenu.addItem(.separator());appMenu.addItem(withTitle:"Quit TNS Studio",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
  let file=NSMenuItem();menu.addItem(file);let fm=NSMenu(title:"File");file.submenu=fm
  for (title,action,key) in [("New Project",#selector(newProject),"n"),("Open Project…",#selector(chooseProject),"o"),("Save Project…",#selector(saveProject),"s"),("Import Material…",#selector(chooseImport),"i"),("Export TNS…",#selector(exportDocument),"e"),("Export Source…",#selector(exportSources),"")]{let item=NSMenuItem(title:title,action:action,keyEquivalent:key);item.target=self;fm.addItem(item)}
  let edit=NSMenuItem();menu.addItem(edit);let em=NSMenu(title:"Edit");edit.submenu=em
  em.addItem(withTitle:"Undo",action:Selector(("undo:")),keyEquivalent:"z");em.addItem(withTitle:"Cut",action:#selector(NSText.cut(_:)),keyEquivalent:"x");em.addItem(withTitle:"Copy",action:#selector(NSText.copy(_:)),keyEquivalent:"c");em.addItem(withTitle:"Paste",action:#selector(NSText.paste(_:)),keyEquivalent:"v");em.addItem(withTitle:"Select All",action:#selector(NSText.selectAll(_:)),keyEquivalent:"a");NSApp.mainMenu=menu
 }
 func button(_ title:String,_ action:Selector)->NSButton{let b=NSButton(title:title,target:self,action:action);b.bezelStyle = .rounded;buttons.append(b);return b}
 func buildWindow(){
  window=NSWindow(contentRect:NSRect(x:0,y:0,width:1100,height:760),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false);window.title="TNS Studio 0.1";window.minSize=NSSize(width:1020,height:700);window.center();window.delegate=self;window.isReleasedWhenClosed=false
  let root=ImportArea(frame:NSRect(x:0,y:0,width:1100,height:760));window.contentView=root;root.allowed={ [weak self] in self?.busy==false };root.receive={ [weak self] in self?.importFiles($0) }
  let toolbar=NSStackView(views:[button("New",#selector(newProject)),button("Open Project…",#selector(chooseProject)),button("Save Project…",#selector(saveProject)),button("Import…",#selector(chooseImport)),button("OCR Import…",#selector(chooseOCR)),button("Export TNS…",#selector(exportDocument)),button("Help",#selector(about))]);toolbar.orientation = .horizontal;toolbar.spacing=8;toolbar.frame=NSRect(x:20,y:16,width:1060,height:32);toolbar.autoresizingMask=[.width];root.addSubview(toolbar)
  let nameLabel=textLabel("Guide title",12,true);nameLabel.frame=NSRect(x:24,y:60,width:80,height:24);root.addSubview(nameLabel)
  docTitle.frame=NSRect(x:110,y:56,width:650,height:28);docTitle.autoresizingMask=[.width];docTitle.delegate=self;root.addSubview(docTitle)
  let offline=textLabel("OFFLINE · LUNA",11,true);offline.frame=NSRect(x:925,y:63,width:150,height:20);offline.autoresizingMask=[.minXMargin];offline.textColor = .secondaryLabelColor;root.addSubview(offline)
  let split=NSSplitView(frame:NSRect(x:20,y:100,width:1060,height:590));split.isVertical=true;split.dividerStyle = .thin;split.autoresizingMask=[.width,.height];root.addSubview(split)
  let sidebar=FlippedView(frame:NSRect(x:0,y:0,width:245,height:590)),pane=FlippedView(frame:NSRect(x:246,y:0,width:814,height:590));split.addArrangedSubview(sidebar);split.addArrangedSubview(pane);split.setPosition(245,ofDividerAt:0)
  template.addItems(withTitles:["Blank note","Worked example","Study checklist","Lua app","Python script"]);template.frame=NSRect(x:0,y:0,width:235,height:28);template.autoresizingMask=[.width];sidebar.addSubview(template)
  let add=button("Add Page",#selector(addPage));add.frame=NSRect(x:0,y:34,width:110,height:30);sidebar.addSubview(add)
  let remove=button("Remove",#selector(removePage));remove.frame=NSRect(x:115,y:34,width:115,height:30);sidebar.addSubview(remove)
  let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier("page"));column.title="Pages";column.width=215;table.addTableColumn(column);table.headerView=nil;table.rowHeight=34;table.delegate=self;table.dataSource=self;table.usesAlternatingRowBackgroundColors=true
  let list=NSScrollView(frame:NSRect(x:0,y:72,width:235,height:468));list.documentView=table;list.hasVerticalScroller=true;list.borderType = .bezelBorder;list.autoresizingMask=[.width,.height];sidebar.addSubview(list)
  let up=button("Move Up",#selector(moveUp)),down=button("Move Down",#selector(moveDown));up.frame=NSRect(x:0,y:550,width:112,height:30);down.frame=NSRect(x:116,y:550,width:115,height:30);up.autoresizingMask=[.minYMargin];down.autoresizingMask=[.minYMargin];sidebar.addSubview(up);sidebar.addSubview(down)
  pageTitle.frame=NSRect(x:14,y:0,width:490,height:28);pageTitle.autoresizingMask=[.width];pageTitle.delegate=self;pane.addSubview(pageTitle)
  kind.addItems(withTitles:["Calculator notes","Lua app page","Python script"]);kind.frame=NSRect(x:520,y:0,width:190,height:28);kind.autoresizingMask=[.minXMargin];kind.target=self;kind.action=#selector(kindChanged);pane.addSubview(kind)
  font.addItems(withTitles:[9,10,11,12,24].map{String($0)});font.frame=NSRect(x:726,y:0,width:70,height:28);font.autoresizingMask=[.minXMargin];font.target=self;font.action=#selector(fontChanged);pane.addSubview(font)
  origin.frame=NSRect(x:14,y:36,width:780,height:40);origin.autoresizingMask=[.width];origin.font = .systemFont(ofSize:11);origin.textColor = .secondaryLabelColor;pane.addSubview(origin)
  let tabs=NSTabView(frame:NSRect(x:8,y:80,width:800,height:460));tabs.autoresizingMask=[.width,.height];pane.addSubview(tabs)
  let item=NSTabViewItem(identifier:"editor");item.label="Edit text";let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.borderType = .bezelBorder;scroll.documentView=editor;editor.isRichText=false;editor.allowsUndo=true;editor.delegate=self;editor.isAutomaticQuoteSubstitutionEnabled=false;editor.isAutomaticDashSubstitutionEnabled=false;editor.isAutomaticTextReplacementEnabled=false;editor.textContainerInset=NSSize(width:12,height:12);editor.frame=NSRect(x:0,y:0,width:760,height:400);editor.minSize=NSSize(width:0,height:0);editor.maxSize=NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude);editor.textContainer?.containerSize=NSSize(width:760,height:CGFloat.greatestFiniteMagnitude);editor.isVerticallyResizable=true;editor.isHorizontallyResizable=false;editor.autoresizingMask=[.width];editor.textContainer?.widthTracksTextView=true;item.view=scroll;tabs.addTabViewItem(item)
  let second=NSTabViewItem(identifier:"preview");second.label="Calculator preview";second.view=preview;tabs.addTabViewItem(second)
  let clean=button("Simplify math symbols",#selector(simplify));clean.frame=NSRect(x:12,y:550,width:190,height:30);clean.autoresizingMask=[.minYMargin];pane.addSubview(clean)
  let hint=textLabel("Review equations and reading order. Diagrams are not converted into editable notes.",11);hint.frame=NSRect(x:216,y:548,width:570,height:38);hint.autoresizingMask=[.width,.minYMargin];hint.textColor = .secondaryLabelColor;pane.addSubview(hint)
  status.frame=NSRect(x:24,y:708,width:1050,height:36);status.autoresizingMask=[.width,.minYMargin];root.addSubview(status)
 }
 func commit(){guard !loading,project.pages.indices.contains(active) else{return};project.title=docTitle.stringValue;project.pages[active].title=pageTitle.stringValue;project.pages[active].text=editor.string;preview.page=project.pages[active];preview.fontSize=project.fontSize;preview.needsDisplay=true}
 func changed(){guard !loading else{return};commit();dirty=true;window.isDocumentEdited=true;table.reloadData();recoveryTimer?.invalidate();recoveryTimer=Timer.scheduledTimer(withTimeInterval:0.8,repeats:false){[weak self] _ in self?.writeRecovery()}}
 func textDidChange(_ note:Notification){changed()}
 func controlTextDidChange(_ note:Notification){changed()}
 func showPage(){loading=true;defer{loading=false};docTitle.stringValue=project.title;active=max(0,min(active,project.pages.count-1));let p=project.pages[active];pageTitle.stringValue=p.title;editor.string=p.text;editor.font=p.kind == .notes ? .systemFont(ofSize:15):.monospacedSystemFont(ofSize:13,weight:.regular);kind.selectItem(at:p.kind == .notes ? 0:p.kind == .lua ? 1:2);font.selectItem(withTitle:String(project.fontSize));origin.stringValue=p.origin.isEmpty ? "Create notes from scratch, or drop a PDF/document into the window.":p.origin;preview.page=p;preview.fontSize=project.fontSize;preview.needsDisplay=true;table.reloadData();table.selectRowIndexes(IndexSet(integer:active),byExtendingSelection:false)}
 func numberOfRows(in tableView:NSTableView)->Int{project.pages.count}
 func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView?{let p=project.pages[row];return textLabel("\(row+1). \(p.title.isEmpty ? "Untitled page":p.title)",12)}
 func tableViewSelectionDidChange(_ note:Notification){guard !loading,!busy,table.selectedRow>=0 else{return};commit();active=table.selectedRow;showPage()}
 func setBusy(_ b:Bool){busy=b;buttons.forEach{$0.isEnabled = !b};editor.isEditable = !b;docTitle.isEnabled = !b;pageTitle.isEnabled = !b;kind.isEnabled = !b;font.isEnabled = !b;table.isEnabled = !b;template.isEnabled = !b}
 func writeRecovery(){guard dirty else{return};do{try FileManager.default.createDirectory(at:recoveryURL.deletingLastPathComponent(),withIntermediateDirectories:true);try JSONEncoder().encode(project).write(to:recoveryURL,options:.atomic)}catch{status.stringValue="Recovery copy could not be saved. Use Save Project to keep your work."}}
 func clearRecovery(){recoveryTimer?.invalidate();try? FileManager.default.removeItem(at:recoveryURL)}
 func restoreRecovery(){guard let data=try? Data(contentsOf:recoveryURL),let p=try? JSONDecoder().decode(Project.self,from:data),(try? validate(p)) != nil else{return};let a=NSAlert();a.messageText="Restore your unsaved guide?";a.addButton(withTitle:"Restore");a.addButton(withTitle:"Discard");if a.runModal() == .alertFirstButtonReturn{project=p;active=0;dirty=true;window.isDocumentEdited=true;showPage()}else{clearRecovery()}}
 func canLeave()->Bool{if busy{alert("Please wait","The import or export is still running.");return false};commit();guard dirty else{return true};let a=NSAlert();a.messageText="Save changes to this guide?";a.addButton(withTitle:"Save");a.addButton(withTitle:"Discard");a.addButton(withTitle:"Cancel");let r=a.runModal();if r == .alertFirstButtonReturn{return save()};if r == .alertSecondButtonReturn{dirty=false;clearRecovery();return true};return false}
 @objc func newProject(){guard canLeave() else{return};project=Project();projectURL=nil;active=0;dirty=false;window.isDocumentEdited=false;showPage()}
 @objc func chooseProject(){guard !busy else{return};let p=NSOpenPanel();p.allowedContentTypes=[UTType(filenameExtension:"tnsproject") ?? .json];if p.runModal() == .OK,let u=p.url{openProject(u)}}
 func openProject(_ url:URL){guard canLeave() else{return};do{let data=try Data(contentsOf:url);guard data.count<=4_000_000 else{throw StudioError("Project file is too large.")};let p=try JSONDecoder().decode(Project.self,from:data);try validate(p);project=p;projectURL=url;active=0;dirty=false;window.isDocumentEdited=false;clearRecovery();showPage();status.stringValue="Opened \(url.lastPathComponent)"}catch{alert("Cannot open project",error.localizedDescription)}}
 @objc func saveProject(){_ = save()}
 func save()->Bool{guard !busy else{return false};commit();let p=NSSavePanel();p.allowedContentTypes=[UTType(filenameExtension:"tnsproject") ?? .json];p.nameFieldStringValue=projectURL?.lastPathComponent ?? project.title+".tnsproject";if let u=projectURL{p.directoryURL=u.deletingLastPathComponent()};guard p.runModal() == .OK,let url=p.url else{return false};do{try validate(project);try JSONEncoder().encode(project).write(to:url,options:.atomic);projectURL=url;dirty=false;window.isDocumentEdited=false;clearRecovery();status.stringValue="Saved editable project.";return true}catch{alert("Cannot save",error.localizedDescription);return false}}
 @objc func addPage(){guard !busy else{return};commit();guard project.pages.count<maxPages else{alert("Page limit","Use up to 40 pages per guide.");return};let t=template.indexOfSelectedItem
  if t==4 || project.pages.contains(where:{$0.kind == .python}) {guard project.pages.count==1 && project.pages[0].text.isEmpty else{alert("Separate Python project","Create a new project for a single Python script.");return}}
  var p=NotePage(title:"Page \(project.pages.count+1)",text:"")
  if t==1{p=NotePage(title:"Worked example",text:"PROBLEM TYPE\nLinear equation\n\nQUESTION\nSolve 2*x + 3 = 11.\n\nSTEPS\n1. Subtract 3: 2*x = 8.\n2. Divide by 2: x = 4.\n\nCALCULATOR ENTRY\n(11-3)/2\n\nANSWER\nx = 4")}
  if t==2{p=NotePage(title:"Study checklist",text:"TOPIC\n\nHOW TO RECOGNIZE IT\n\nFORMULA\n\nCALCULATOR ENTRY\nUse parentheses around fractions and negative numbers.\n\nWORKED EXAMPLE\n\nCOMMON MISTAKES\n")}
  if t==3{p=NotePage(title:"My Lua app",kind:.lua,text:"function on.paint(gc)\n  gc:drawString(\"Hello, calculator!\", 10, 20, \"top\")\nend\n")}
  if t==4{p=NotePage(title:"main",kind:.python,text:"# TI-Nspire CX II Python\nprint('Hello, calculator!')\n")}
  if project.pages.count==1 && project.pages[0].text.isEmpty{project.pages=[p];active=0}else{project.pages.append(p);active=project.pages.count-1};dirty=true;showPage();changed()
 }
 @objc func removePage(){guard !busy else{return};commit();let a=NSAlert();a.messageText="Remove this page?";a.addButton(withTitle:"Cancel");a.addButton(withTitle:"Remove");guard a.runModal() == .alertSecondButtonReturn else{return};project.pages.remove(at:active);if project.pages.isEmpty{project.pages=[NotePage(title:"Page 1",text:"")]};active=min(active,project.pages.count-1);showPage();changed()}
 func move(_ delta:Int){guard !busy else{return};commit();let dest=active+delta;guard project.pages.indices.contains(dest) else{return};project.pages.swapAt(active,dest);active=dest;showPage();changed()}
 @objc func moveUp(){move(-1)}
 @objc func moveDown(){move(1)}
 @objc func kindChanged(){guard !busy else{return};let k:PageKind=kind.indexOfSelectedItem==0 ? .notes:kind.indexOfSelectedItem==1 ? .lua:.python;if k == .python && project.pages.count != 1{alert("Separate Python project","Python scripts need a one-page project.");showPage();return};project.pages[active].kind=k;changed();showPage()}
 @objc func fontChanged(){project.fontSize=Int(font.titleOfSelectedItem ?? "11") ?? 11;changed()}
 @objc func simplify(){guard !busy else{return};editor.insertText(cleanMath(editor.string),replacementRange:NSRange(location:0,length:(editor.string as NSString).length));changed();status.stringValue="Symbols simplified. Review sqrt(...) parentheses and every equation; Undo restores the previous text."}
 @objc func chooseImport(){chooseFiles(false)}
 @objc func chooseOCR(){chooseFiles(true)}
 func chooseFiles(_ force:Bool){guard !busy else{return};let p=NSOpenPanel();p.allowsMultipleSelection=true;p.canChooseDirectories=false;p.message=force ? "Recognize text in scanned PDFs or images. Review all equations afterward.":"Import PDF, Word, text, images, Lua, or Python. You can also drag files into the window.";if p.runModal() == .OK{importFiles(p.urls,forceOCR:force)}}
 func importFiles(_ urls:[URL],forceOCR:Bool=false){guard !busy,!urls.isEmpty else{return};commit();setBusy(true);status.stringValue="Importing…"
  DispatchQueue.global(qos:.userInitiated).async{var result:[NotePage]=[];do{for u in urls{result += try importPages(u,forceOCR:forceOCR){msg in DispatchQueue.main.async{self.status.stringValue=msg}}};let pages=result;DispatchQueue.main.async{self.setBusy(false);var next=self.project;if next.pages.count==1 && next.pages[0].text.isEmpty{next.pages=[];next.title=String(urls[0].deletingPathExtension().lastPathComponent.prefix(120))};let first=next.pages.count;next.pages+=pages;do{try validate(next);self.project=next;self.active=first;self.showPage();self.changed();self.status.stringValue="Imported \(pages.count) pages. Review equations, OCR, and reading order before export."}catch{self.alert("Import needs a smaller or separate project",error.localizedDescription)}}}catch{DispatchQueue.main.async{self.setBusy(false);self.status.stringValue="Import stopped; existing pages were preserved.";self.alert("Could not import",error.localizedDescription)}}}
 }
 @objc func exportDocument(){guard !busy else{return};commit();do{try validate(project)}catch{alert("Check the project",error.localizedDescription);return};let p=NSSavePanel();p.allowedContentTypes=[UTType(filenameExtension:"tns") ?? .data];p.nameFieldStringValue=project.title+".tns";guard p.runModal() == .OK,let url=p.url else{return};let copy=project;setBusy(true);status.stringValue="Building calculator document…";DispatchQueue.global(qos:.userInitiated).async{do{try exportTNS(copy,to:url);DispatchQueue.main.async{self.setBusy(false);self.status.stringValue="Created \(url.lastPathComponent). Transfer it with NspireDesk. Save your project to edit it later.";NSWorkspace.shared.activateFileViewerSelecting([url])}}catch{DispatchQueue.main.async{self.setBusy(false);self.status.stringValue="Export failed; the destination was not replaced.";self.alert("Could not export",error.localizedDescription)}}}}
 @objc func exportSources(){guard !busy else{return};commit();let p=NSSavePanel();p.nameFieldStringValue=project.title+" Source";p.message="Create a new folder containing your editable Lua/Python and Luna XML source.";guard p.runModal() == .OK,let url=p.url else{return};do{try exportSource(project,to:url);NSWorkspace.shared.activateFileViewerSelecting([url]);status.stringValue="Saved editable sources for your Luna workflow."}catch{alert("Cannot export source",error.localizedDescription)}}
 @objc func about(){alert("TNS Studio 0.1","Create calculator notes from PDFs, Word documents, text, and local OCR. Save an editable .tnsproject, then export a .tns and transfer it with NspireDesk.\n\nNotes are scrollable Lua pages, not the native Notes editor. Up/Down scroll; Left/Right jump; +/− changes font size. Use the calculator's page controls to change pages.\n\nImport preserves text, not diagrams or page layout. OCR can misread math. Lua gets a syntax check; Python is packaged without checking calculator compatibility. Existing .tns files cannot be reopened as editable source.\n\nOffline · Luna 2.1 · TI-Nspire CX II non-CAS. No calculator is required to create files.")}
}
