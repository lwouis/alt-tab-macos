platform :osx, '10.12'

target 'alt-tab-macos' do
  use_frameworks!
  pod 'LetsMove', '1.24'
  pod 'Sparkle', '1.23.0'
  pod 'ShortcutRecorder', :git => 'https://github.com/Kentzo/ShortcutRecorder.git', :branch => 'issue-114'
  pod 'SwiftyMarkdown', '1.1.0'
  pod 'Preferences', '1.0.1'

  post_install do |installer|
    # remove incorrect whitespace from ShortcutRecorder license
    # remote first 2 lines (i.e. title)
    # force wrap text as some licenses are and some are not
    system('cat -s Pods/Target\\ Support\\ Files/Pods-alt-tab-macos/Pods-alt-tab-macos-acknowledgements.markdown'\
      '| tail -n +2 '\
      '| sed -e "s/^ \{12\}/      /" '\
      '| sed -e "s/^ \{7\}/    /" '\
      '| fold -w 80 -s > docs/ACKNOWLEDGMENTS.md')
  end
end
