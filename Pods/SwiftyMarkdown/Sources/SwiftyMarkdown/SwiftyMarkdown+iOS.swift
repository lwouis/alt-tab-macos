//
//  SwiftyMarkdown+macOS.swift
//  SwiftyMarkdown
//
//  Created by Simon Fairbairn on 17/12/2019.
//  Copyright © 2019 Voyage Travel Apps. All rights reserved.
//

import Foundation

#if !os(macOS)
import UIKit

extension SwiftyMarkdown {
	
	func font( for line : SwiftyLine, characterOverride : CharacterStyle? = nil ) -> UIFont {
		let textStyle : UIFont.TextStyle
		var fontName : String?
		var fontSize : CGFloat?
		
		var globalBold = false
		var globalItalic = false
		
		let style : FontProperties
		// What type are we and is there a font name set?
		switch line.lineStyle as! MarkdownLineStyle {
		case .h1:
			style = self.h1
			if #available(iOS 9, *) {
				textStyle = UIFont.TextStyle.title1
			} else {
				textStyle = UIFont.TextStyle.headline
			}
		case .h2:
			style = self.h2
			if #available(iOS 9, *) {
				textStyle = UIFont.TextStyle.title2
			} else {
				textStyle = UIFont.TextStyle.headline
			}
		case .h3:
			style = self.h3
			if #available(iOS 9, *) {
				textStyle = UIFont.TextStyle.title2
			} else {
				textStyle = UIFont.TextStyle.subheadline
			}
		case .h4:
			style = self.h4
			textStyle = UIFont.TextStyle.headline
		case .h5:
			style = self.h5
			textStyle = UIFont.TextStyle.subheadline
		case .h6:
			style = self.h6
			textStyle = UIFont.TextStyle.footnote
		case .codeblock:
			style = self.code
			textStyle = UIFont.TextStyle.body
		case .blockquote:
			style = self.blockquotes
			textStyle = UIFont.TextStyle.body
		default:
			style = self.body
			textStyle = UIFont.TextStyle.body
		}
		
		fontName = style.fontName
		fontSize = style.fontSize
		switch style.fontStyle {
		case .bold:
			globalBold = true
		case .italic:
			globalItalic = true
		case .boldItalic:
			globalItalic = true
			globalBold = true
		case .normal:
			break
		}

		if fontName == nil {
			fontName = body.fontName
		}
		
		if let characterOverride = characterOverride {
			switch characterOverride {
			case .code:
				fontName = code.fontName ?? fontName
				fontSize = code.fontSize
			case .link:
				fontName = link.fontName ?? fontName
				fontSize = link.fontSize
			case .bold:
				fontName = bold.fontName ?? fontName
				fontSize = bold.fontSize
				globalBold = true
			case .italic:
				fontName = italic.fontName ?? fontName
				fontSize = italic.fontSize
				globalItalic = true
			case .strikethrough:
				fontName = strikethrough.fontName ?? fontName
				fontSize = strikethrough.fontSize
			default:
				break
			}
		}
		
		fontSize = fontSize == 0.0 ? nil : fontSize
		var font : UIFont
		if let existentFontName = fontName {
			font = UIFont.preferredFont(forTextStyle: textStyle)
			let finalSize : CGFloat
			if let existentFontSize = fontSize {
				finalSize = existentFontSize
			} else {
				let styleDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: textStyle)
				finalSize = styleDescriptor.fontAttributes[.size] as? CGFloat ?? CGFloat(14)
			}
			
			if let customFont = UIFont(name: existentFontName, size: finalSize)  {
				let fontMetrics = UIFontMetrics(forTextStyle: textStyle)
				font = fontMetrics.scaledFont(for: customFont)
			} else {
				font = UIFont.preferredFont(forTextStyle: textStyle)
			}
		} else {
			font = UIFont.preferredFont(forTextStyle: textStyle)
		}
		
		if globalItalic, let italicDescriptor = font.fontDescriptor.withSymbolicTraits(.traitItalic) {
			font = UIFont(descriptor: italicDescriptor, size: 0)
		}
		if globalBold, let boldDescriptor = font.fontDescriptor.withSymbolicTraits(.traitBold) {
			font = UIFont(descriptor: boldDescriptor, size: 0)
		}
		
		return font
		
	}
	
	func color( for line : SwiftyLine ) -> UIColor {
		// What type are we and is there a font name set?
		switch line.lineStyle as! MarkdownLineStyle {
		case .yaml:
			return body.color
		case .h1, .previousH1:
			return h1.color
		case .h2, .previousH2:
			return h2.color
		case .h3:
			return h3.color
		case .h4:
			return h4.color
		case .h5:
			return h5.color
		case .h6:
			return h6.color
		case .body:
			return body.color
		case .codeblock:
			return code.color
		case .blockquote:
			return blockquotes.color
		case .unorderedList, .unorderedListIndentFirstOrder, .unorderedListIndentSecondOrder, .orderedList, .orderedListIndentFirstOrder, .orderedListIndentSecondOrder:
			return body.color

		}
	}
	
}
#endif
