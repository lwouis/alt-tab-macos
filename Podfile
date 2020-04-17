platform :osx, '10.12'

target 'alt-tab-macos' do
  use_frameworks!
  pod 'LetsMove', '1.24'
  pod 'Sparkle', '1.23.0'
  pod 'ShortcutRecorder', :git => 'https://github.com/Kentzo/ShortcutRecorder.git', :branch => 'issue-114'

  post_install do |installer|
    require 'fileutils'
    FileUtils.cp_r('Pods/Target Support Files/Pods-alt-tab-macos/Pods-alt-tab-macos-acknowledgements.markdown', 'docs/ACKNOWLEDGMENTS.md', :remove_destination => true)
  end
end
