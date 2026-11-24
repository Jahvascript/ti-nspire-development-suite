import Foundation
import AppKit
import PDFKit
import Vision
import ImageIO

struct StudioError:LocalizedError {let message:String;var errorDescription:String?{message};init(_ s:String){message=s}}
enum PageKind:String,Codable {case notes,lua,python}
struct NotePage:Codable {var title:String;var kind:PageKind = .notes;var text:String;var origin:String = ""}
struct Project:Codable {var version=1;var title="Untitled guide";var fontSize=11;var pages=[NotePage(title:"Page 1",text:"")]}
let maxPages=40
func validate(_ p:Project)throws {
 guard p.version==1 else{throw StudioError("This project was saved by an unsupported version.")}
 guard !p.pages.isEmpty && p.pages.count<=maxPages else{throw StudioError("Use between 1 and 40 pages per project.")}
 guard [9,10,11,12,24].contains(p.fontSize) else{throw StudioError("Choose a calculator font size: 9, 10, 11, 12, or 24.")}
 guard !p.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && p.title.count<=120 else{throw StudioError("Give the guide a title of 1–120 characters.")}
 guard p.pages.reduce(0,{$0+$1.text.utf8.count})<=512_000 else{throw StudioError("This project is too large. Split it into guides of less than 512 KB of text.")}
 for page in p.pages {
  guard page.title.count<=120 && !page.title.contains("\0") && !page.text.contains("\0") else{throw StudioError("A page has an invalid title or a null character.")}
 }
 if p.pages.contains(where:{$0.kind == .python}) && (p.pages.count != 1 || p.pages[0].kind != .python){throw StudioError("Python is exported as a separate one-script document. Keep it in its own project.")}
}
func xmlEscape(_ s:String)->String {s.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"\"",with:"&quot;").replacingOccurrences(of:"'",with:"&apos;")}
func luaQuote(_ s:String)->String {
 var out="\""
 for b in s.utf8 {if b==34{out+="\\\""}else if b==92{out+="\\\\"}else if b<32 || b>=127{out+=String(format:"\\%03d",Int(b))}else{out.append(Character(UnicodeScalar(b)))}}
 return out+"\""
}
func normalized(_ s:String)->String {s.replacingOccurrences(of:"\r\n",with:"\n").replacingOccurrences(of:"\r",with:"\n").replacingOccurrences(of:"\u{000c}",with:"\n\n")}
func cleanMath(_ s:String)->String {
 var t=s
 for (a,b) in [("−","-"),("×","*"),("÷","/"),("≤","<="),("≥",">="),("≠","!="),("π","pi"),("²","^2"),("³","^3"),("√","sqrt"),("“","\""),("”","\""),("’","'")]{t=t.replacingOccurrences(of:a,with:b)}
 return t
}
func splitText(_ text:String,limit:Int=6000)->[String] {
 var remaining=normalized(text),parts:[String]=[]
 while remaining.count>limit {
  let cut=remaining.index(remaining.startIndex,offsetBy:limit)
  let prefix=remaining[..<cut]
  let split=prefix.lastIndex(of:"\n").map{remaining.distance(from:remaining.startIndex,to:$0)>limit/2 ? remaining.index(after:$0):cut} ?? cut
  parts.append(String(remaining[..<split]));remaining=String(remaining[split...])
 }
 if !remaining.isEmpty || parts.isEmpty{parts.append(remaining)}
 return parts
}
func resource(_ name:String)->URL {Bundle.main.resourceURL!.appendingPathComponent(name)}
func helper(_ name:String)->URL {Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/"+name)}
func runTool(_ executable:URL,_ args:[String],timeout:Double=30)throws->String {
 let fm=FileManager.default,folder=fm.temporaryDirectory.appendingPathComponent("tnsstudio-tool-"+UUID().uuidString)
 try fm.createDirectory(at:folder,withIntermediateDirectories:true);defer{try? fm.removeItem(at:folder)}
 let outURL=folder.appendingPathComponent("stdout"),errURL=folder.appendingPathComponent("stderr")
 fm.createFile(atPath:outURL.path,contents:nil);fm.createFile(atPath:errURL.path,contents:nil)
 let out=try FileHandle(forWritingTo:outURL),err=try FileHandle(forWritingTo:errURL)
 defer{try? out.close();try? err.close()}
 let task=Process();task.executableURL=executable;task.arguments=args;task.standardOutput=out;task.standardError=err
 try task.run()
 let timeoutWork=DispatchWorkItem{if task.isRunning{task.terminate()}}
 DispatchQueue.global().asyncAfter(deadline:.now()+timeout,execute:timeoutWork)
 task.waitUntilExit();timeoutWork.cancel();try out.synchronize();try err.synchronize()
 let text=String(data:try Data(contentsOf:outURL),encoding:.utf8) ?? ""
 let errors=String(data:try Data(contentsOf:errURL),encoding:.utf8) ?? ""
 guard task.terminationStatus==0 else{let detail=errors.isEmpty ? text:errors;throw StudioError(detail.isEmpty ? "The converter stopped or exceeded its time limit.":detail)}
 return text
}

func ocr(_ image:CGImage)throws->String {
 let req=VNRecognizeTextRequest();req.recognitionLevel = .accurate;req.usesLanguageCorrection=true;req.automaticallyDetectsLanguage=true;req.usesCPUOnly=true
 do{try VNImageRequestHandler(cgImage:image,options:[:]).perform([req])}catch{throw StudioError("Local text recognition could not run: \(error.localizedDescription)\nTry a PDF with selectable text, or paste the text into a blank page.")}
 return (req.results ?? []).compactMap{$0.topCandidates(1).first?.string}.joined(separator:"\n")
}
func pdfImage(_ page:PDFPage)throws->CGImage {
 guard let ref=page.pageRef else{throw StudioError("This PDF page cannot be rendered for text recognition.")}
 let box=ref.getBoxRect(.cropBox);guard box.width>0 && box.height>0 else{throw StudioError("Invalid PDF page dimensions.")}
 let scale=min(2.5,2600/max(box.width,box.height));let w=max(1,Int(box.width*scale)),h=max(1,Int(box.height*scale))
 guard let ctx=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{throw StudioError("Cannot create PDF image.")}
 ctx.setFillColor(CGColor(gray:1,alpha:1));ctx.fill(CGRect(x:0,y:0,width:w,height:h))
 ctx.concatenate(ref.getDrawingTransform(.cropBox,rect:CGRect(x:0,y:0,width:w,height:h),rotate:0,preserveAspectRatio:true));ctx.drawPDFPage(ref)
 guard let image=ctx.makeImage() else{throw StudioError("Cannot render PDF page.")};return image
}
func importPages(_ url:URL,forceOCR:Bool=false,progress:(String)->Void={_ in})throws->[NotePage] {
 let size=(try url.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0
 guard size<=30*1024*1024 else{throw StudioError("Import files smaller than 30 MB. Split a large document first.")}
 let name=url.deletingPathExtension().lastPathComponent,ext=url.pathExtension.lowercased()
 var pages:[NotePage]=[]
 func append(_ text:String,_ title:String,_ origin:String){let chunks=splitText(text);for (i,c) in chunks.enumerated(){pages.append(NotePage(title:String((title+(chunks.count>1 ? " · \(i+1)":"")).prefix(120)),text:c,origin:origin))}}
 if ext=="pdf" {
  guard let pdf=PDFDocument(url:url),!pdf.isLocked else{throw StudioError("The PDF cannot be read or is password-locked. Save an unlocked copy first.")}
  guard pdf.pageCount<=maxPages else{throw StudioError("This PDF has \(pdf.pageCount) pages. Import a PDF with at most 40 pages.")}
  for i in 0..<pdf.pageCount {
   progress("Reading PDF page \(i+1) of \(pdf.pageCount)…")
   guard let page=pdf.page(at:i) else{throw StudioError("Cannot read PDF page \(i+1).")}
   var text=normalized(page.string ?? ""),recognized=false
   if forceOCR || text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {progress("Recognizing PDF page \(i+1)…");text=try ocr(pdfImage(page));recognized=true}
   if text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty{text="[No readable text was found. Add notes for the diagram or page here.]"}
   append(text,"\(name) · p\(i+1)","\(url.lastPathComponent), page \(i+1)"+(recognized ? " · OCR: verify every equation":" · extracted text: check reading order"))
  }
 }else if ["png","jpg","jpeg","tif","tiff","heic","bmp"].contains(ext){
  guard let src=CGImageSourceCreateWithURL(url as CFURL,nil),let img=CGImageSourceCreateThumbnailAtIndex(src,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:2600,kCGImageSourceCreateThumbnailWithTransform:true] as [CFString:Any] as CFDictionary) else{throw StudioError("Cannot read this image.")}
  progress("Recognizing text in \(url.lastPathComponent)…");let text=try ocr(img)
  guard !text.isEmpty else{throw StudioError("No readable text was found in the image.")};append(text,name,"\(url.lastPathComponent) · OCR: verify equations")
 }else if ["docx","doc","rtf"].contains(ext){
  progress("Extracting document text…")
  let text=try runTool(URL(fileURLWithPath:"/usr/bin/textutil"),["-convert","txt","-stdout",url.path])
  guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{throw StudioError("The document has no extractable text. Export it as PDF and try OCR.")};append(text,name,"\(url.lastPathComponent) · text only; verify equations and tables")
 }else if ["txt","md","csv","tsv","lua","py"].contains(ext){
  let text=normalized(try String(contentsOf:url,encoding:.utf8))
  if ext=="lua" || ext=="py"{pages=[NotePage(title:String(name.prefix(120)),kind:ext=="lua" ? .lua:.python,text:text,origin:url.lastPathComponent)]}
  else{append(text,name,"\(url.lastPathComponent) · text import")}
 }else{throw StudioError("Supported imports: PDF, DOCX, DOC, RTF, TXT, Markdown, CSV, images, Lua and Python. Existing .tns files need their original source or Studio project to edit.")}
 guard pages.count<=maxPages else{throw StudioError("The extracted text needs more than 40 pages. Split the source document and import a smaller part.")}
 return pages
}
func script(_ page:NotePage,font:Int,reader:String)->String {
 page.kind == .lua ? page.text : "TITLE="+luaQuote(page.title)+"\nBODY="+luaQuote(page.text)+"\nFONT=\(font)\n"+reader
}
func problemXML(_ p:Project,reader:String)->String {
 var xml="<prob xmlns=\"urn:TI.Problem\" ver=\"1.0\" pbname=\"\(xmlEscape(p.title))\"><sym></sym>"
 for page in p.pages {xml+="<card clay=\"0\" h1=\"10000\" h2=\"10000\" w1=\"10000\" w2=\"10000\"><isDummyCard>0</isDummyCard><flag>0</flag><wdgt xmlns:sc=\"urn:TI.ScriptApp\" type=\"TI.ScriptApp\" ver=\"1.0\"><sc:mFlags>0</sc:mFlags><sc:value>-1</sc:value><sc:script version=\"512\" id=\"0\">"+xmlEscape(script(page,font:p.fontSize,reader:reader))+"</sc:script></wdgt></card>"}
 return xml+"</prob>"
}
func exportTNS(_ project:Project,to destination:URL)throws {
 try validate(project)
 let fm=FileManager.default,temp=fm.temporaryDirectory.appendingPathComponent("tnsstudio-"+UUID().uuidString)
 try fm.createDirectory(at:temp,withIntermediateDirectories:true);defer{try? fm.removeItem(at:temp)}
 let input:URL
 if project.pages[0].kind == .python {
  input=temp.appendingPathComponent("main.py");try project.pages[0].text.write(to:input,atomically:true,encoding:.utf8)
 }else{
  let reader=try String(contentsOf:resource("notes.lua"),encoding:.utf8)
  for (i,page) in project.pages.enumerated(){let f=temp.appendingPathComponent("page\(i+1).lua");try script(page,font:project.fontSize,reader:reader).write(to:f,atomically:true,encoding:.utf8)
   do{_ = try runTool(helper("luac"),["-p",f.path])}catch{throw StudioError("Page \(i+1), \(page.title):\n\(error.localizedDescription)")}
  }
  input=temp.appendingPathComponent("Problem1.xml");try problemXML(project,reader:reader).write(to:input,atomically:true,encoding:.utf8)
 }
 let built=temp.appendingPathComponent("Guide.tns");_ = try runTool(helper("luna"),[input.path,built.path])
 let data=try Data(contentsOf:built);guard data.count>40 && data.starts(with:Data("*TIMLP".utf8)) else{throw StudioError("Luna did not produce a recognized TNS document.")}
 try data.write(to:destination,options:.atomic)
}

func exportSource(_ project:Project,to folder:URL)throws {
 try validate(project)
 let fm=FileManager.default
 guard !fm.fileExists(atPath:folder.path) else{throw StudioError("Choose a new folder name for the source export.")}
 try fm.createDirectory(at:folder,withIntermediateDirectories:true)
 do {
  try JSONEncoder().encode(project).write(to:folder.appendingPathComponent("Guide.tnsproject"),options:.atomic)
  if project.pages[0].kind == .python {try project.pages[0].text.write(to:folder.appendingPathComponent("main.py"),atomically:true,encoding:.utf8)}
  else {
   let reader=try String(contentsOf:resource("notes.lua"),encoding:.utf8)
   for (i,page) in project.pages.enumerated(){try script(page,font:project.fontSize,reader:reader).write(to:folder.appendingPathComponent("Page\(i+1).lua"),atomically:true,encoding:.utf8)}
   try problemXML(project,reader:reader).write(to:folder.appendingPathComponent("Problem1.xml"),atomically:true,encoding:.utf8)
  }
 }catch{try? fm.removeItem(at:folder);throw error}
}
