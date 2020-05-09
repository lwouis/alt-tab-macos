platform :osx, '10.12'

target 'alt-tab-macos' do
  use_frameworks!
  pod 'LetsMove', :git => 'https://github.com/lwouis/LetsMove.git', :branch => 'master'
  pod 'Sparkle', '1.23.0'
  pod 'ShortcutRecorder', :git => 'https://github.com/Kentzo/ShortcutRecorder.git', :branch => 'issue-114'
  pod 'SwiftyMarkdown', '1.1.0'
  pod 'Preferences', '1.0.1'

  post_install do |installer|
    system('scripts/update_acknowledgments.sh')
  end
end
