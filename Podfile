platform :osx, '10.12'

target 'alt-tab-macos' do
  use_frameworks!
  pod 'LetsMove', :git => 'https://github.com/lwouis/LetsMove.git', :commit => '7abf4daed1a25218f2b52f2dfd190aee5a50071c'
  pod 'Sparkle', :podspec => 'https://raw.githubusercontent.com/lwouis/Sparkle/fix-iframe-popup-1.24/Sparkle.podspec'
  pod 'ShortcutRecorder', :git => 'https://github.com/lwouis/ShortcutRecorder.git', :branch => 'alt-tab-current'
  pod 'SwiftyMarkdown', '1.1.0'
  pod 'AppCenter/Crashes', '4.3.0'
  pod 'SwiftyBeaver', '1.9.0'
end

target 'unit-tests' do
  use_frameworks!
  pod 'ShortcutRecorder', :git => 'https://github.com/lwouis/ShortcutRecorder.git', :branch => 'alt-tab-current'
  # disable code signing which is unnecessary for tests
  post_install do |installer|
    installer.pods_project.targets.each do |target|
      target.build_configurations.each do |config|
        config.build_settings['CODE_SIGNING_REQUIRED'] = 'NO'
        config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
      end
    end
  end
end
