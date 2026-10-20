#if MAC_RECEIVER_ENABLED
import AppKit

/// Navigation has no enclosing bezel; each page keeps the established 映桥 theme.
final class UnifiedDashboard:NSView {
 let pages=NSTabView()
 let navigation=NSSegmentedControl(labels:["平板扩展屏","Mac 互联"],trackingMode:.selectOne,target:nil,action:nil)
 init(pad:NSView,mac:NSView,receive:Bool){
  super.init(frame:NSRect(x:0,y:0,width:880,height:660))
  wantsLayer=true;layer?.backgroundColor=BridgeTheme.fog.cgColor
  pages.tabViewType = .noTabsNoBorder;pages.drawsBackground=false
  for (name,view) in [("pad",pad),("mac",mac)] {
   let item=NSTabViewItem(identifier:name);item.view=view;pages.addTabViewItem(item)
  }
  navigation.target=self;navigation.action=#selector(selectPage)
  navigation.segmentStyle = .texturedRounded
  navigation.selectedSegment=receive ? 1:0
  addSubview(pages);addSubview(navigation);selectPage()
 }
 required init?(coder:NSCoder){nil}
 override func layout(){
  super.layout()
  navigation.frame=NSRect(x:28,y:bounds.height-42,width:250,height:28)
  pages.frame=NSRect(x:0,y:0,width:bounds.width,height:max(0,bounds.height-48))
 }
 @objc private func selectPage(){pages.selectTabViewItem(at:navigation.selectedSegment)}
}
#endif
