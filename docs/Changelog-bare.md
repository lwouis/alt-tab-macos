---
layout: bare
---

{% include_relative Changelog.md %}

<style>#google_translate_element,.skiptranslate{display:none;}body{top:0!important;}</style>
<div id="google_translate_element"></div>
<script>
    function getUserLanguage() {
        if (navigator.languages && navigator.languages.length > 0) {
            // Chinese is the only exception where google translate needs the full code
            // see https://sites.google.com/site/opti365/translate_codes
            const l = navigator.languages[0]
            if (l.length > 2 && l !== "zh-CN" && l !== "zh-TW") {
              return l.slice(0, 2)
            }
            return l
        }
        return "en"
    }

    function googleTranslateElementInit() {
        new google.translate.TranslateElement({
            pageLanguage: 'en', 
            includedLanguages: getUserLanguage(),
             autoDisplay: false
         }, 'google_translate_element')
        setTimeout(() => {
            var a = document.querySelector("#google_translate_element select")
            a.selectedIndex = 1
            a.dispatchEvent(new Event('change'))
        }, 1000)
    }
    
    const userLanguage = getUserLanguage()
    if (userLanguage !== "en") {
        let script = document.createElement("script")  
        script.src = "https://translate.google.com/translate_a/element.js?cb=googleTranslateElementInit"
        document.head.appendChild(script)
    }
</script>
