// NspireDesk USB service. GPL-3.0-or-later. No network operations.
use anyhow::{bail,ensure,Context,Result};
use libnspire::{Handle,VID,PID_CX2,dir::EntryType,info::{Info,Battery}};
use rusb::GlobalContext;
use serde_json::{json,Value};
use std::{io::{self,BufRead,Write},fs::{self,OpenOptions},path::Path,time::{Duration,Instant}};
extern "C" {
 fn nspire_cx2_last_error() -> *const std::os::raw::c_char;
 fn nspire_cx2_clear_error();
}
fn connection_error(e:libnspire::Error)->anyhow::Error {
 let detail=unsafe {std::ffi::CStr::from_ptr(nspire_cx2_last_error())}.to_string_lossy();
 if detail.is_empty(){e.into()}else{anyhow::Error::new(e).context(detail.into_owned())}
}
const MAX_FILE:u64=64*1024*1024;
fn emit(v:Value){println!("{}",v);let _=io::stdout().flush();}
fn string<'a>(v:&'a Value,k:&str)->Result<&'a str>{v[k].as_str().with_context(||format!("Missing {k}"))}
fn remote(path:&str)->Result<String>{
 ensure!(path.starts_with('/') && path.len()<=230,"Calculator path must start with / and be at most 230 bytes.");
 ensure!(!path.chars().any(|c|c.is_control()||c=='\\'),"Invalid calculator path.");
 ensure!(!path.split('/').any(|x|x==".."||x=="."),"Relative path components are not allowed.");
 Ok(if path=="/"{"/".into()}else{path.trim_end_matches('/').to_string()})
}
fn file_name(path:&Path)->Result<String>{let n=path.file_name().and_then(|s|s.to_str()).context("Invalid file name")?;ensure!(!n.is_empty()&&n.len()<=120&&!n.chars().any(|c|c.is_control()||c=='/'||c=='\\'),"Invalid file name");Ok(n.into())}
fn join(dir:&str,name:&str)->Result<String>{remote(&format!("{}/{}",dir.trim_end_matches('/'),name))}
fn limited_read(p:&Path,max:u64)->Result<Vec<u8>>{let m=fs::metadata(p)?;ensure!(m.is_file()&&m.len()<=max,"File is too large or is not a regular file.");Ok(fs::read(p)?)}
fn progress(id:&Value,total:usize,phase:&'static str)->impl FnMut(usize){let id=id.clone();let mut tick=Instant::now()-Duration::from_secs(1);move|remaining|{if tick.elapsed()>Duration::from_millis(150)||remaining==0 {emit(json!({"id":id,"event":"progress","phase":phase,"done":total.saturating_sub(remaining),"total":total}));tick=Instant::now();}}}
fn read_remote(h:&Handle<GlobalContext>,path:&str,id:&Value)->Result<Vec<u8>>{
 let attr=h.file_attr(path)?;ensure!(attr.entry_type()==EntryType::File,"Select a file, not a folder.");let size=attr.size();ensure!(size<=MAX_FILE,"File exceeds 64 MB transfer limit.");
 // The upstream reader sends the final ACK only with spare buffer capacity.
 let mut buf=vec![0;size as usize+1];let n=h.read_file(path,&mut buf,&mut progress(id,size as usize,"Receiving"))?;
 ensure!(n==size as usize,"Received size differs from file listing; no local file was saved.");buf.truncate(n);Ok(buf)
}
fn save_new(path:&Path,data:&[u8])->Result<()> {
 // Never truncate a user's existing file. An incomplete newly created file is removed.
 let mut f=OpenOptions::new().write(true).create_new(true).open(path).context("Destination already exists or cannot be created. Choose a new filename.")?;
 if let Err(e)=f.write_all(data).and_then(|_|f.sync_all()){drop(f);let _=fs::remove_file(path);return Err(e.into())}Ok(())
}
fn png_bytes(image:libnspire::Image)->Result<Vec<u8>>{
 ensure!(image.width>0&&image.height>0&&image.width<=1024&&image.height<=1024,"Invalid screenshot dimensions");
 let rgb=rgb565(&image.data,image.width as usize*image.height as usize,image.bpp)?;
 let mut out=Vec::new();{let mut enc=png::Encoder::new(&mut out,image.width.into(),image.height.into());enc.set_color(png::ColorType::Rgb);enc.set_depth(png::BitDepth::Eight);enc.write_header()?.write_image_data(&rgb)?;}Ok(out)
}
fn rgb565(data:&[u8],pixels:usize,bpp:u8)->Result<Vec<u8>>{
 ensure!(bpp==16&&data.len()==pixels*2,"This build expects a CX II 16-bit color screenshot.");
 Ok(data.chunks_exact(2).flat_map(|b|{let c=u16::from_le_bytes([b[0],b[1]]);[((c>>11)&31) as u32*255/31,((c>>5)&63) as u32*255/63,(c&31) as u32*255/31].map(|x|x as u8)}).collect())
}
fn validate_os(path:&Path,info:&Info)->Result<()> { validate_os_fields(path,&info.os_extension,info.battery) }
fn validate_os_fields(path:&Path,os_extension:&str,battery:Battery)->Result<()> {
 let ext=path.extension().and_then(|x|x.to_str()).unwrap_or("");let want=os_extension.trim_start_matches('.');
 ensure!(!want.is_empty()&&ext.eq_ignore_ascii_case(want),"Wrong OS file type. This calculator reports .{}; selected .{}",want,ext);
 ensure!(matches!(want.to_ascii_lowercase().as_str(),"tco2"|"tcc2"|"tct2"),"Unsupported OS family for this CX II-only build.");
 ensure!(!matches!(battery,Battery::Low|Battery::Unknown(_)),"Battery must not be low or unknown before an OS update.");Ok(())
}
#[derive(Default)]struct Service{handle:Option<Handle<GlobalContext>>,info:Option<Info>}
impl Service{
 fn run(&mut self,v:&Value)->Result<Value>{let id=&v["id"];let op=string(v,"op")?;
 match op {
 "scan"=>{let mut a=vec![];for d in rusb::devices()?.iter(){if let Ok(desc)=d.device_descriptor(){if desc.vendor_id()==VID&&desc.product_id()==PID_CX2{a.push(json!({"bus":d.bus_number(),"address":d.address(),"label":format!("TI-Nspire CX II — USB {}:{}",d.bus_number(),d.address())}));}}}return Ok(json!({"devices":a}));},
 "disconnect"=>{self.handle=None;self.info=None;return Ok(json!({"message":"Disconnected"}));},
 "connect"=>{ensure!(self.handle.is_none(),"Disconnect the current calculator first.");let bus=v["bus"].as_u64().context("Choose a USB device")?;let addr=v["address"].as_u64().context("Choose a USB device")?;for d in rusb::devices()?.iter(){let desc=d.device_descriptor()?;if d.bus_number() as u64==bus&&d.address() as u64==addr&&desc.vendor_id()==VID&&desc.product_id()==PID_CX2{let raw=d.open().context("Opening the selected USB calculator")?;unsafe {nspire_cx2_clear_error()};let h=Handle::new(raw).map_err(connection_error).context("Starting the CX II USB handshake")?;let info=h.info().context("Reading calculator information after the CX II handshake")?;let value=serde_json::to_value(&info)?;self.info=Some(info);self.handle=Some(h);return Ok(value)}}bail!("Calculator not found. Reconnect the USB cable and scan again.");},_=>{}
 }
 let h=self.handle.as_ref().context("Connect a calculator first.")?;
 match op {
 "list"=>{let p=remote(string(v,"path")?)?;let list=h.list_dir(&p)?;let entries:Vec<_>=list.iter().map(|e|json!({"name":e.name().to_string_lossy(),"size":e.size(),"folder":e.entry_type()==EntryType::Directory})).collect();Ok(json!({"path":p,"entries":entries}))},
 "upload"=>{let dir=remote(string(v,"path")?)?;ensure!(dir!="/","Open a calculator folder before sending documents.");let local=Path::new(string(v,"local")?);ensure!(local.extension().and_then(|x|x.to_str()).map(|x|x.eq_ignore_ascii_case("tns")).unwrap_or(false),"Only .tns documents can be sent here. Use Update OS for firmware.");let data=limited_read(local,MAX_FILE)?;ensure!(data.starts_with(b"*TIMLP"),"This is not a recognized TNS document.");let name=file_name(local)?;let dest=join(&dir,&name)?;
 let listing=h.list_dir(&dir)?;if let Some(e)=listing.iter().find(|e|e.name().to_string_lossy()==name){ensure!(e.entry_type()==EntryType::File,"A folder already has this name.");ensure!(v["replace"]==true,"A file named {} already exists. Confirm replacement or rename your file.",name);}
 h.write_file(&dest,&data,&mut progress(id,data.len(),"Sending"))?;
 let check=read_remote(h,&dest,id).context("File sent, but read-back verification failed. Inspect the calculator before retrying.")?;ensure!(check==data,"File sent but read-back verification did not match.");Ok(json!({"message":format!("Sent and verified {name}"),"bytes":data.len()}))},
 "download"=>{let path=remote(string(v,"path")?)?;let dest=Path::new(string(v,"local")?);ensure!(!dest.exists(),"Destination exists; choose a new name.");let data=read_remote(h,&path,id)?;save_new(dest,&data)?;Ok(json!({"message":"Saved to Mac","local":dest,"bytes":data.len()}))},
 "mkdir"=>{let p=remote(string(v,"path")?)?;ensure!(p!="/","Cannot create the root folder");h.create_dir(&p)?;Ok(json!({"message":"Folder created"}))},
 "screenshot"=>{let dest=Path::new(string(v,"local")?);ensure!(!dest.exists(),"Destination exists; choose a new name.");let png=png_bytes(h.screenshot()?)?;save_new(dest,&png)?;Ok(json!({"message":"Screenshot saved","local":dest}))},
 "os"=>{ensure!(v["confirmed"]==true,"OS installation requires confirmation.");let path=Path::new(string(v,"local")?);let current=h.info()?;validate_os(path,&current)?;ensure!(Some(current.id.as_str())==v["deviceID"].as_str(),"Calculator identity changed; review the update again.");let data=limited_read(path,128*1024*1024)?;ensure!(data.len()>=1024*1024,"OS image is unexpectedly small.");h.send_os(&data,&mut progress(id,data.len(),"Sending OS — keep USB connected"))?;self.handle=None;self.info=None;Ok(json!({"message":"OS transfer completed. Check the handheld installation/restart, then reconnect."}))},
 "exit_test"=>{ensure!(v["confirmed"]==true,"Exit test mode requires confirmation.");let dir="/Press-to-Test";let root=h.list_dir("/")?;
 if let Some(e)=root.iter().find(|e|e.name().to_string_lossy()=="Press-to-Test"){ensure!(e.entry_type()==EntryType::Directory,"Press-to-Test exists but is not a folder.");}else{h.create_dir(dir)?;}
 let marker=include_bytes!("../../resources/Exit Test Mode.tns");
 let result=h.write_file("/Press-to-Test/Exit Test Mode.tns",marker,&mut progress(id,marker.len(),"Sending exit request"));
 // A reboot can drop the link before the final acknowledgement. Never assert that mode changed.
 self.handle=None;self.info=None;
 match result {Ok(())=>Ok(json!({"message":"Exit request delivered. The calculator should restart. Verify Press-to-Test is off on the handheld."})),Err(e)=>bail!("Exit request was attempted, but completion could not be confirmed ({e}). Check whether the calculator restarted before trying again.")}
 },_=>bail!("Unknown operation")
 }
 }
}
fn main(){let mut service=Service::default();for line in io::stdin().lock().lines(){let line=match line{Ok(l)=>l,Err(_)=>break};if line.len()>65536 {emit(json!({"ok":false,"error":"Request too large"}));continue}let v:Value=match serde_json::from_str(&line){Ok(v)=>v,Err(e)=>{emit(json!({"ok":false,"error":e.to_string()}));continue}};let result=service.run(&v);match result{Ok(data)=>emit(json!({"id":v["id"],"ok":true,"connected":service.handle.is_some(),"data":data})),Err(e)=>{if e.downcast_ref::<libnspire::Error>().is_some(){service.handle=None;service.info=None;}emit(json!({"id":v["id"],"ok":false,"connected":service.handle.is_some(),"error":format!("{e:#}")}));}}}}
#[cfg(test)]mod tests{
 use super::*;
 #[test]fn paths(){for bad in ["relative","/../x","/a/./b","/bad\0name","/a\\b"]{assert!(remote(bad).is_err());}assert_eq!(remote("/docs/").unwrap(),"/docs");assert_eq!(join("/","x.tns").unwrap(),"/x.tns");}
 #[test]fn colors(){let rgb=rgb565(&[0,0xf8,0xe0,7,31,0,255,255],4,16).unwrap();assert_eq!(rgb,vec![255,0,0,0,255,0,0,0,255,255,255,255]);assert!(rgb565(&[0],1,16).is_err());}
 #[test]fn not_connected(){let mut s=Service::default();for op in ["list","upload","download","os","exit_test","screenshot"]{assert!(s.run(&json!({"op":op})).is_err());}}
 #[test]fn no_clobber(){let p=std::env::temp_dir().join(format!("nspiredesk-test-{}",std::process::id()));let _=fs::remove_file(&p);save_new(&p,b"original").unwrap();assert!(save_new(&p,b"replacement").is_err());assert_eq!(fs::read(&p).unwrap(),b"original");fs::remove_file(p).unwrap();}
 #[test]fn firmware_guards(){
  assert!(validate_os_fields(Path::new("system.tco2"),".tco2",Battery::Ok).is_ok());
  assert!(validate_os_fields(Path::new("system.tcc2"),"tco2",Battery::Powered).is_err());
  assert!(validate_os_fields(Path::new("system.tco2"),"tco2",Battery::Low).is_err());
  assert!(validate_os_fields(Path::new("system.tco2"),"tco2",Battery::Unknown(7)).is_err());
  assert!(validate_os_fields(Path::new("system.tnc"),"tnc",Battery::Ok).is_err());
 }
 #[test]fn png_roundtrip(){
  let bytes=png_bytes(libnspire::Image{width:2,height:1,bpp:16,data:vec![0,248,224,7]}).unwrap();
  let mut reader=png::Decoder::new(std::io::Cursor::new(bytes)).read_info().unwrap();
  let mut data=vec![0;reader.output_buffer_size()];let frame=reader.next_frame(&mut data).unwrap();
  assert_eq!((frame.width,frame.height),(2,1));assert_eq!(data,vec![255,0,0,0,255,0]);
 }

}
