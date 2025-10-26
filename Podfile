def deployment_target_from_xcconfig()
    xcconfig_path = 'config/base.xcconfig'
    File.foreach(xcconfig_path) do |line|
        if line.start_with?('MACOSX_DEPLOYMENT_TARGET')
            target = line.split("=").last.strip
            puts "MACOSX_DEPLOYMENT_TARGET: #{target}"
            return target
        end
    end
    puts "\e[31mCouldn't read MACOSX_DEPLOYMENT_TARGET from #{xcconfig_path}\e[0m"
    exit 1
end

deployment_target = deployment_target_from_xcconfig()

platform :osx, deployment_target

target 'alt-tab-macos' do
  use_frameworks!
  pod 'LetsMove', :git => 'https://github.com/lwouis/LetsMove.git', :commit => '7abf4daed1a25218f2b52f2dfd190aee5a50071c'
  pod 'Sparkle', :podspec => 'https://raw.githubusercontent.com/lwouis/Sparkle/fix-iframe-popup-1.24/Sparkle.podspec'
  pod 'ShortcutRecorder', :git => 'https://github.com/lwouis/ShortcutRecorder.git', :branch => 'alt-tab-current'
  pod 'AppCenter/Crashes', '4.3.0'
  pod 'SwiftyBeaver', '1.9.0'
end

target 'unit-tests' do
  use_frameworks!
  pod 'ShortcutRecorder', :git => 'https://github.com/lwouis/ShortcutRecorder.git', :branch => 'alt-tab-current'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      # disable code signing which is unnecessary for pods
      config.build_settings['CODE_SIGNING_REQUIRED'] = 'NO'
      config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
    end
  end
end
