// Insert only into the chosen window. Babji may return focus from its own UI,
// but must never switch away from an unrelated application.
async function deliver({destination,ownPid,capture,restore,paste,copy,text,trace=()=>{}}){
 try{
  const foreground=await capture();trace('paste-focus',{expectedApp:destination.app,expectedHandle:destination.handle,actualApp:foreground.app,actualHandle:foreground.handle,ownWindow:foreground.pid===ownPid});
  if(foreground.handle===destination.handle&&foreground.pid!==destination.pid)throw new Error('The original window changed.');
  if(foreground.pid===ownPid&&foreground.handle!==destination.handle)await restore(destination);
  await paste(destination.handle,text);
  return {status:'inserted',app:destination.app,message:'Pasted into '+destination.app};
 }catch(error){
  let copied=false;try{await copy(text);copied=true;}catch{}
  trace('paste-failed',{reason:error.message,copied});
  return {status:'failed',app:destination.app,copied,message:copied?'Could not insert into '+destination.app+'. Text copied; click your text field and press Ctrl + V.':'Could not insert into '+destination.app+'. Your text is saved in History.'};
 }
}
module.exports={deliver};
