import Cocoa
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let screen = NSScreen.screens[0].frame
let window = NSWindow(contentRect:NSRect(x:screen.minX+100,y:screen.maxY-520,width:360,height:220),
  styleMask:[.titled,.closable],backing:.buffered,defer:false)
window.title="fruler-region-fixture"
window.isReleasedWhenClosed=false
let button=NSButton(title:"Region fixture control",target:nil,action:nil)
button.frame=NSRect(x:40,y:60,width:180,height:32)
window.contentView?.addSubview(button)
let observer=DistributedNotificationCenter.default().addObserver(
  forName:Notification.Name("dev.fruler.integration.raiseRegionFixture"),object:nil,queue:.main) { _ in
    app.activate(ignoringOtherApps:true)
    window.makeKeyAndOrderFront(nil)
}
window.orderFrontRegardless()
print("ready");fflush(stdout)
app.run()
