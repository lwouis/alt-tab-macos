//
//  SwiftyTokeniser.swift
//  SwiftyMarkdown
//
//  Created by Simon Fairbairn on 16/12/2019.
//  Copyright © 2019 Voyage Travel Apps. All rights reserved.
//
import Foundation
import os.log

extension OSLog {
	private static var subsystem = "SwiftyTokeniser"
	static let tokenising = OSLog(subsystem: subsystem, category: "Tokenising")
	static let styling = OSLog(subsystem: subsystem, category: "Styling")
}

// Tag definition
public protocol CharacterStyling {
	func isEqualTo( _ other : CharacterStyling ) -> Bool
}

public enum SpaceAllowed {
	case no
	case bothSides
	case oneSide
	case leadingSide
	case trailingSide
}

public enum Cancel {
    case none
    case allRemaining
    case currentSet
}

public struct CharacterRule : CustomStringConvertible {
	public let openTag : String
	public let intermediateTag : String?
	public let closingTag : String?
	public let escapeCharacter : Character?
	public let styles : [Int : [CharacterStyling]]
	public var minTags : Int = 1
	public var maxTags : Int = 1
	public var spacesAllowed : SpaceAllowed = .oneSide
	public var cancels : Cancel = .none
	
	public var description: String {
		return "Character Rule with Open tag: \(self.openTag) and current styles : \(self.styles) "
	}
	
	public init(openTag: String, intermediateTag: String? = nil, closingTag: String? = nil, escapeCharacter: Character? = nil, styles: [Int : [CharacterStyling]] = [:], minTags : Int = 1, maxTags : Int = 1, cancels : Cancel = .none) {
		self.openTag = openTag
		self.intermediateTag = intermediateTag
		self.closingTag = closingTag
		self.escapeCharacter = escapeCharacter
		self.styles = styles
		self.minTags = minTags
		self.maxTags = maxTags
		self.cancels = cancels
	}
}

// Token definition
public enum TokenType {
	case repeatingTag
	case openTag
	case intermediateTag
	case closeTag
	case string
	case escape
	case replacement
}



public struct Token {
	public let id = UUID().uuidString
	public let type : TokenType
	public let inputString : String
	public fileprivate(set) var metadataString : String? = nil
	public fileprivate(set) var characterStyles : [CharacterStyling] = []
	public fileprivate(set) var count : Int = 0
	public fileprivate(set) var shouldSkip : Bool = false
	public fileprivate(set) var tokenIndex : Int = -1
	public fileprivate(set) var isProcessed : Bool = false
	public fileprivate(set) var isMetadata : Bool = false
	public var outputString : String {
		get {
			switch self.type {
			case .repeatingTag:
				if count <= 0 {
					return ""
				} else {
					let range = inputString.startIndex..<inputString.index(inputString.startIndex, offsetBy: self.count)
					return String(inputString[range])
				}
			case .openTag, .closeTag, .intermediateTag:
				return (self.isProcessed || self.isMetadata) ? "" : inputString
			case .escape, .string:
				return (self.isProcessed || self.isMetadata) ? "" : inputString
			case .replacement:
				return self.inputString
			}
		}
	}
	public init( type : TokenType, inputString : String, characterStyles : [CharacterStyling] = []) {
		self.type = type
		self.inputString = inputString
		self.characterStyles = characterStyles
	}
	
	func newToken( fromSubstring string: String,  isReplacement : Bool) -> Token {
		var newToken = Token(type: (isReplacement) ? .replacement : .string , inputString: string, characterStyles: self.characterStyles)
		newToken.metadataString = self.metadataString
		newToken.isMetadata = self.isMetadata
		newToken.isProcessed = self.isProcessed
		return newToken
	}
}

extension Sequence where Iterator.Element == Token {
    var oslogDisplay: String {
		return "[\"\(self.map( {  ($0.outputString.isEmpty) ? "\($0.type): \($0.inputString)" : $0.outputString }).joined(separator: "\", \""))\"]"
    }
}

public class SwiftyTokeniser {
	let rules : [CharacterRule]
	var replacements : [String : [Token]] = [:]
	
	var enableLog = (ProcessInfo.processInfo.environment["SwiftyTokeniserLogging"] != nil)
	
	public init( with rules : [CharacterRule] ) {
		self.rules = rules
	}
	
	
	/// This goes through every CharacterRule in order and applies it to the input string, tokenising the string
	/// if there are any matches.
	///
	/// The for loop in the while loop (yeah, I know) is there to separate strings from within tags to
	/// those outside them.
	///
	/// e.g. "A string with a \[link\]\(url\) tag" would have the "link" text tokenised separately.
	///
	/// This is to prevent situations like **\[link**\](url) from returing a bold string.
	///
	/// - Parameter inputString: A string to have the CharacterRules in `self.rules` applied to
	public func process( _ inputString : String ) -> [Token] {
		guard rules.count > 0 else {
			return [Token(type: .string, inputString: inputString)]
		}

		var currentTokens : [Token] = []
		var mutableRules = self.rules
		
		
		
		while !mutableRules.isEmpty {
			let nextRule = mutableRules.removeFirst()
			
			if enableLog {
				os_log("------------------------------", log: .tokenising, type: .info)
				os_log("RULE: %@", log: OSLog.tokenising, type:.info , nextRule.description)
			}
	
			if currentTokens.isEmpty {
				// This means it's the first time through
				currentTokens = self.applyStyles(to: self.scan(inputString, with: nextRule), usingRule: nextRule)
				continue
			}
			
			var outerStringTokens : [Token] = []
			var innerStringTokens : [Token] = []
			var isOuter = true
			for idx in 0..<currentTokens.count {
				let nextToken = currentTokens[idx]
				if nextToken.type == .openTag && nextToken.isProcessed {
					isOuter = false
				}
				if nextToken.type == .closeTag {
					let ref = UUID().uuidString
					outerStringTokens.append(Token(type: .replacement, inputString: ref))
					innerStringTokens.append(nextToken)
					self.replacements[ref] = self.handleReplacementTokens(innerStringTokens, with: nextRule)
					innerStringTokens.removeAll()
					isOuter = true
					continue
				}
				(isOuter) ? outerStringTokens.append(nextToken) : innerStringTokens.append(nextToken)
			}
			
			currentTokens = self.handleReplacementTokens(outerStringTokens, with: nextRule)
			
			var finalTokens : [Token] = []
			for token in currentTokens {
				guard token.type == .replacement else {
					finalTokens.append(token)
					continue
				}
				if let hasReplacement = self.replacements[token.inputString] {
					if enableLog {
						os_log("Found replacement for %@", log: .tokenising, type: .info, token.inputString)
					}
					
					for var repToken in hasReplacement {
						guard repToken.type == .string else {
							finalTokens.append(repToken)
							continue
						}
						for style in token.characterStyles {
							if !repToken.characterStyles.contains(where: { $0.isEqualTo(style)}) {
								repToken.characterStyles.append(contentsOf: token.characterStyles)
							}
						}
						
						finalTokens.append(repToken)
					}
				}
			}
			currentTokens = finalTokens
			
			
			// Each string could have additional tokens within it, so they have to be scanned as well with the current rule.
			// The one string token might then be exploded into multiple more tokens
		}

		if enableLog {
			os_log("=====RULE PROCESSING COMPLETE=====", log: .tokenising, type: .info)
			os_log("==================================", log: .tokenising, type: .info)
		}
		
		return currentTokens
	}
	
	
	
	/// In order to reinsert the original replacements into the new string token, the replacements
	/// need to be searched for in the incoming string one by one.
	///
	/// Using the `newToken(fromSubstring:isReplacement:)` function ensures that any metadata and character styles
	/// are passed over into the newly created tokens.
	///
	/// E.g. A string token that has an `outputString` of "This string AAAAA-BBBBB-CCCCC replacements", with
	/// a characterStyle of `bold` for the entire string, needs to be separated into the following tokens:
	///
	/// - `string`: "This string "
	/// - `replacement`: "AAAAA-BBBBB-CCCCC"
	/// - `string`: " replacements"
	///
	/// Each of these need to have a character style of `bold`.
	///
	/// - Parameters:
	///   - replacements: An array of `replacement` tokens
	///   - token: The new `string` token that may contain replacement IDs contained in the `replacements` array
	func reinsertReplacements(_ replacements : [Token], from stringToken : Token ) -> [Token] {
		guard !stringToken.outputString.isEmpty && !replacements.isEmpty else {
			return [stringToken]
		}
		var outputTokens : [Token] = []
		let scanner = Scanner(string: stringToken.outputString)
		scanner.charactersToBeSkipped = nil
		
		// Remove any replacements that don't appear in the incoming string
		var repTokens = replacements.filter({ stringToken.outputString.contains($0.inputString) })
		
		var testString = "\n"
		while !scanner.isAtEnd {
			var outputString : String = ""
			if repTokens.count > 0 {
				testString = repTokens.removeFirst().inputString
			}
			
			if #available(iOS 13.0, OSX 10.15, watchOS 6.0, tvOS 13.0, *) {
				if let nextString = scanner.scanUpToString(testString) {
					outputString = nextString
					outputTokens.append(stringToken.newToken(fromSubstring: outputString, isReplacement: false))
					if let outputToken = scanner.scanString(testString) {
						outputTokens.append(stringToken.newToken(fromSubstring: outputToken, isReplacement: true))
					}
				} else if let outputToken = scanner.scanString(testString) {
					outputTokens.append(stringToken.newToken(fromSubstring: outputToken, isReplacement: true))
				}
			} else {
				var oldString : NSString? = nil
				var tokenString : NSString? = nil
				scanner.scanUpTo(testString, into: &oldString)
				if let nextString = oldString {
					outputString = nextString as String
					outputTokens.append(stringToken.newToken(fromSubstring: outputString, isReplacement: false))
					scanner.scanString(testString, into: &tokenString)
					if let outputToken = tokenString as String? {
						outputTokens.append(stringToken.newToken(fromSubstring: outputToken, isReplacement: true))
					}
				} else {
					scanner.scanString(testString, into: &tokenString)
					if let outputToken = tokenString as String? {
						outputTokens.append(stringToken.newToken(fromSubstring: outputToken, isReplacement: true))
					}
				}
			}
		}
		return outputTokens
	}
	
	
	/// This function is necessary because a previously tokenised string might have
	///
	/// Consider a previously tokenised string, where AAAAA-BBBBB-CCCCC represents a replaced \[link\](url) instance.
	///
	/// The incoming tokens will look like this:
	///
	/// - `string`: "A \*\*Bold"
	/// - `replacement` : "AAAAA-BBBBB-CCCCC"
	/// - `string`: " with a trailing string**"
	///
	///	However, because the scanner can only tokenise individual strings, passing in the string values
	///	of these tokens individually and applying the styles will not correctly detect the starting and
	///	ending `repeatingTag` instances. (e.g. the scanner will see "A \*\*Bold", and then "AAAAA-BBBBB-CCCCC",
	///	and finally " with a trailing string\*\*")
	///
	///	The strings need to be combined, so that they form a single string:
	///	A \*\*Bold AAAAA-BBBBB-CCCCC with a trailing string\*\*.
	///	This string is then parsed and tokenised so that it looks like this:
	///
	/// - `string`: "A "
	///	- `repeatingTag`: "\*\*"
	///	- `string`: "Bold AAAAA-BBBBB-CCCCC with a trailing string"
	///	- `repeatingTag`: "\*\*"
	///
	///	Finally, the replacements from the original incoming token array are searched for and pulled out
	///	of this new string, so the final result looks like this:
	///
	/// - `string`: "A "
	///	- `repeatingTag`: "\*\*"
	///	- `string`: "Bold "
	///	- `replacement`: "AAAAA-BBBBB-CCCCC"
	///	- `string`: " with a trailing string"
	///	- `repeatingTag`: "\*\*"
	///
	/// - Parameters:
	///   - tokens: The tokens to be combined, scanned, re-tokenised, and merged
	///   - rule: The character rule currently being applied
	func scanReplacementTokens( _ tokens : [Token], with rule : CharacterRule ) -> [Token] {
		guard tokens.count > 0 else {
			return []
		}
		
		let combinedString = tokens.map({ $0.outputString }).joined()
		
		let nextTokens = self.scan(combinedString, with: rule)
		var replacedTokens = self.applyStyles(to: nextTokens, usingRule: rule)
		
		/// It's necessary here to check to see if the first token (which will always represent the styles
		/// to be applied from previous scans) has any existing metadata or character styles and apply them
		/// to *all* the string and replacement tokens found by the new scan.
		for idx in 0..<replacedTokens.count {
			guard replacedTokens[idx].type == .string || replacedTokens[idx].type == .replacement else {
				continue
			}
			if tokens.first!.metadataString != nil && replacedTokens[idx].metadataString == nil {
				replacedTokens[idx].metadataString = tokens.first!.metadataString
			}
			replacedTokens[idx].characterStyles.append(contentsOf: tokens.first!.characterStyles)
		}
		
		// Swap the original replacement tokens back in
		let replacements = tokens.filter({ $0.type == .replacement })
		var outputTokens : [Token] = []
		for token in replacedTokens {
			guard token.type == .string else {
				outputTokens.append(token)
				continue
			}
			outputTokens.append(contentsOf: self.reinsertReplacements(replacements, from: token))
		}
		
		return outputTokens
	}
	
	
	
	/// This function ensures that only concurrent `string` and `replacement` tokens are processed together.
	///
	/// i.e. If there is an existing `repeatingTag` token between two strings, then those strings will be
	/// processed individually. This prevents incorrect parsing of strings like "\*\*\_Should only be bold\*\*\_"
	///
	/// - Parameters:
	///   - incomingTokens: A group of tokens whose string tokens and replacement tokens should be combined and re-tokenised
	///   - rule: The current rule being processed
	func handleReplacementTokens( _ incomingTokens : [Token], with rule : CharacterRule) -> [Token] {
	
		// Only combine string and replacements that are next to each other.
		var newTokenSet : [Token] = []
		var currentTokenSet : [Token] = []
		for i in 0..<incomingTokens.count {
			guard incomingTokens[i].type == .string || incomingTokens[i].type == .replacement else {
				newTokenSet.append(contentsOf: self.scanReplacementTokens(currentTokenSet, with: rule))
				newTokenSet.append(incomingTokens[i])
				currentTokenSet.removeAll()
				continue
			}
			guard !incomingTokens[i].isProcessed && !incomingTokens[i].isMetadata && !incomingTokens[i].shouldSkip else {
				newTokenSet.append(contentsOf: self.scanReplacementTokens(currentTokenSet, with: rule))
				newTokenSet.append(incomingTokens[i])
				currentTokenSet.removeAll()
				continue
			}
			currentTokenSet.append(incomingTokens[i])
		}
		newTokenSet.append(contentsOf: self.scanReplacementTokens(currentTokenSet, with: rule))

		return newTokenSet
	}
	
	
	func handleClosingTagFromOpenTag(withIndex index : Int, in tokens: inout [Token], following rule : CharacterRule ) {
		
		guard rule.closingTag != nil else {
			return
		}
		guard let closeTokenIdx = tokens.firstIndex(where: { $0.type == .closeTag && !$0.isProcessed }) else {
			return
		}
		
		var metadataIndex = index
		// If there's an intermediate tag, get the index of that
		if rule.intermediateTag != nil {
			guard let nextTokenIdx = tokens.firstIndex(where: { $0.type == .intermediateTag  && !$0.isProcessed }) else {
				return
			}
			metadataIndex = nextTokenIdx
			let styles : [CharacterStyling] = rule.styles[1] ?? []
			for i in index..<nextTokenIdx {
				for style in styles {
					if !tokens[i].characterStyles.contains(where: { $0.isEqualTo(style )}) {
						tokens[i].characterStyles.append(style)
					}
				}
			}
		}

		var metadataString : String = ""
		for i in metadataIndex..<closeTokenIdx {
			if tokens[i].type == .string {
				metadataString.append(tokens[i].outputString)
				tokens[i].isMetadata = true
			}
		}
		
		for i in index..<metadataIndex {
			if tokens[i].type == .string {
				tokens[i].metadataString = metadataString
			}
		}
		
		tokens[closeTokenIdx].isProcessed = true
		tokens[metadataIndex].isProcessed = true
		tokens[index].isProcessed = true
	}
	
	
	/// This is here to manage how opening tags are matched with closing tags when they're all the same
	/// character.
	///
	/// Of course, because Markdown is about as loose as a spec can be while still being considered any
	/// kind of spec, the number of times this character repeats causes different effects. Then there
	/// is the ill-defined way it should work if the number of opening and closing tags are different.
	///
	/// - Parameters:
	///   - index: The index of the current token in the loop
	///   - tokens: An inout variable of the loop tokens of interest
	///   - rule: The character rule being applied
	func handleClosingTagFromRepeatingTag(withIndex index : Int, in tokens: inout [Token], following rule : CharacterRule) {
		let theToken = tokens[index]
		
		if enableLog {
		os_log("Found repeating tag with tag count: %i, tags: %@, current rule open tag: %@", log: .tokenising, type: .info, theToken.count, theToken.inputString, rule.openTag )
		}
		
		guard theToken.count > 0 else {
			return
		}
		
		let startIdx = index
		var endIdx : Int? = nil
		
		let maxCount = (theToken.count > rule.maxTags) ? rule.maxTags : theToken.count
		// Try to find exact match first
		if let nextTokenIdx = tokens.firstIndex(where: { $0.inputString.first == theToken.inputString.first && $0.type == theToken.type && $0.count == theToken.count && $0.id != theToken.id && !$0.isProcessed }) {
			endIdx = nextTokenIdx
		}
		
		if endIdx == nil, let nextTokenIdx = tokens.firstIndex(where: { $0.inputString.first == theToken.inputString.first && $0.type == theToken.type && $0.count >= 1 && $0.id != theToken.id  && !$0.isProcessed }) {
			endIdx = nextTokenIdx
		}
		guard let existentEnd = endIdx else {
			return
		}
		
		
		let styles : [CharacterStyling] = rule.styles[maxCount] ?? []
		for i in startIdx..<existentEnd {
			for style in styles {
				if !tokens[i].characterStyles.contains(where: { $0.isEqualTo(style )}) {
					tokens[i].characterStyles.append(style)
				}
			}
			if rule.cancels == .allRemaining {
				tokens[i].shouldSkip = true
			}
		}
		
		let maxEnd = (tokens[existentEnd].count > rule.maxTags) ? rule.maxTags : tokens[existentEnd].count
		tokens[index].count = theToken.count - maxEnd
		tokens[existentEnd].count = tokens[existentEnd].count - maxEnd
		if maxEnd < rule.maxTags {
			self.handleClosingTagFromRepeatingTag(withIndex: index, in: &tokens, following: rule)
		} else {
			tokens[existentEnd].isProcessed = true
			tokens[index].isProcessed = true
		}
		
		
	}
	
	func applyStyles( to tokens : [Token], usingRule rule : CharacterRule ) -> [Token] {
		var mutableTokens : [Token] = tokens
		
		if enableLog {
			os_log("Applying styles to tokens: %@", log: .tokenising, type: .info,  tokens.oslogDisplay )
		}
		for idx in 0..<mutableTokens.count {
			let token = mutableTokens[idx]
			switch token.type {
			case .escape:
			if enableLog {
				os_log("Found escape: %@", log: .tokenising, type: .info, token.inputString )
			}
			case .repeatingTag:
				self.handleClosingTagFromRepeatingTag(withIndex: idx, in: &mutableTokens, following: rule)
			case .openTag:
				let theToken = mutableTokens[idx]
				if enableLog {
					os_log("Found repeating tag with tags: %@, current rule open tag: %@", log: .tokenising, type: .info, theToken.inputString, rule.openTag )
				}
								
				guard rule.closingTag != nil else {
					
					// If there's an intermediate tag, get the index of that
					
					// Get the index of the closing tag
					
					continue
				}
				self.handleClosingTagFromOpenTag(withIndex: idx, in: &mutableTokens, following: rule)
				
				
			case .intermediateTag:
				let theToken = mutableTokens[idx]
				if enableLog {
					os_log("Found intermediate tag with tag count: %i, tags: %@", log: .tokenising, type: .info, theToken.count, theToken.inputString )
				}
				
			case .closeTag:
				let theToken = mutableTokens[idx]
					if enableLog {
						os_log("Found close tag with tag count: %i, tags: %@", log: .tokenising, type: .info, theToken.count, theToken.inputString )
				}
				
			case .string:
				let theToken = mutableTokens[idx]
				if enableLog {
					if theToken.isMetadata {
						os_log("Found Metadata: %@", log: .tokenising, type: .info, theToken.inputString )
					} else {
						os_log("Found String: %@", log: .tokenising, type: .info, theToken.inputString )
					}
					if let hasMetadata = theToken.metadataString {
						os_log("...with metadata: %@", log: .tokenising, type: .info, hasMetadata )
					}
				}
				
			case .replacement:
				if enableLog {
					os_log("Found replacement with ID: %@", log: .tokenising, type: .info, mutableTokens[idx].inputString )
				}
			}
		}
		return mutableTokens
	}
	
	
	func scan( _ string : String, with rule : CharacterRule) -> [Token] {
		let scanner = Scanner(string: string)
		scanner.charactersToBeSkipped = nil
		var tokens : [Token] = []
		var set = CharacterSet(charactersIn: "\(rule.openTag)\(rule.intermediateTag ?? "")\(rule.closingTag ?? "")")
		if let existentEscape = rule.escapeCharacter {
			set.insert(charactersIn: String(existentEscape))
		}
		
		var openTagFound = false
		var openingString = ""
		while !scanner.isAtEnd {
			
			if #available(iOS 13.0, OSX 10.15, watchOS 6.0, tvOS 13.0, *) {
				if let start = scanner.scanUpToCharacters(from: set) {
					openingString.append(start)
				}
			} else {
				var string : NSString?
				scanner.scanUpToCharacters(from: set, into: &string)
				if let existentString = string as String? {
					openingString.append(existentString)
				}
				// Fallback on earlier versions
			}
			
			let lastChar : String?
			if #available(iOS 13.0, OSX 10.15, watchOS 6.0, tvOS 13.0, *) {
				lastChar = ( scanner.currentIndex > string.startIndex ) ? String(string[string.index(before: scanner.currentIndex)..<scanner.currentIndex]) : nil
			} else {
				if let scanLocation = string.index(string.startIndex, offsetBy: scanner.scanLocation, limitedBy: string.endIndex) {
					lastChar = ( scanLocation > string.startIndex ) ? String(string[string.index(before: scanLocation)..<scanLocation]) : nil
				} else {
					lastChar = nil
				}
				
			}
			let maybeFoundChars : String?
			if #available(iOS 13.0, OSX 10.15, watchOS 6.0, tvOS 13.0, *) {
				maybeFoundChars = scanner.scanCharacters(from: set )
			} else {
				var string : NSString?
				scanner.scanCharacters(from: set, into: &string)
				maybeFoundChars = string as String?
			}
			
			let nextChar : String?
			if #available(iOS 13.0, OSX 10.15,  watchOS 6.0,tvOS 13.0, *) {
				 nextChar = (scanner.currentIndex != string.endIndex) ? String(string[scanner.currentIndex]) : nil
			} else {
				if let scanLocation = string.index(string.startIndex, offsetBy: scanner.scanLocation, limitedBy: string.endIndex) {
					nextChar = (scanLocation != string.endIndex) ? String(string[scanLocation]) : nil
				} else {
					nextChar = nil
				}
				
			}
			
			guard let foundChars = maybeFoundChars else {
				tokens.append(Token(type: .string, inputString: "\(openingString)"))
				openingString = ""
				continue
			}
			
			if foundChars == rule.openTag && foundChars.count < rule.minTags {
				openingString.append(foundChars)
				continue
			}
			
			if !validateSpacing(nextCharacter: nextChar, previousCharacter: lastChar, with: rule) {
				let escapeString = String("\(rule.escapeCharacter ?? Character(""))")
				var escaped = foundChars.replacingOccurrences(of: "\(escapeString)\(rule.openTag)", with: rule.openTag)
				if let hasIntermediateTag = rule.intermediateTag {
					escaped = foundChars.replacingOccurrences(of: "\(escapeString)\(hasIntermediateTag)", with: hasIntermediateTag)
				}
				if let existentClosingTag = rule.closingTag {
					escaped = foundChars.replacingOccurrences(of: "\(escapeString)\(existentClosingTag)", with: existentClosingTag)
				}
				
				openingString.append(escaped)
				continue
			}

			var cumulativeString = ""
			var openString = ""
			var intermediateString = ""
			var closedString = ""
			var maybeEscapeNext = false
			
			
			func addToken( for type : TokenType ) {
				var inputString : String
				switch type {
				case .openTag:
					inputString = openString
				case .intermediateTag:
					inputString = intermediateString
				case .closeTag:
					inputString = closedString
				default:
					inputString = ""
				}
				guard !inputString.isEmpty else {
					return
				}
				guard inputString.count >= rule.minTags else {
					return
				}
				
				if !openingString.isEmpty {
					tokens.append(Token(type: .string, inputString: "\(openingString)"))
					openingString = ""
				}
				let actualType : TokenType = ( rule.intermediateTag == nil && rule.closingTag == nil ) ? .repeatingTag : type
				
				var token = Token(type: actualType, inputString: inputString)
				if rule.closingTag == nil {
					token.count = inputString.count
				}
				
				tokens.append(token)
				
				switch type {
				case .openTag:
					openString = ""
				case .intermediateTag:
					intermediateString = ""
				case .closeTag:
					closedString = ""
				default:
					break
				}
			}
			
			// Here I am going through and adding the characters in the found set to a cumulative string.
			// If there is an escape character, then the loop stops and any open tags are tokenised.
			for char in foundChars {
				cumulativeString.append(char)
				if maybeEscapeNext {
					
					var escaped = cumulativeString
					if String(char) == rule.openTag || String(char) == rule.intermediateTag || String(char) == rule.closingTag {
						escaped = String(cumulativeString.replacingOccurrences(of: String(rule.escapeCharacter ?? Character("")), with: ""))
					}
					
					openingString.append(escaped)
					cumulativeString = ""
					maybeEscapeNext = false
				}
				if let existentEscape = rule.escapeCharacter {
					if cumulativeString == String(existentEscape) {
						maybeEscapeNext = true
						addToken(for: .openTag)
						addToken(for: .intermediateTag)
						addToken(for: .closeTag)
						continue
					}
				}
				
				
				if cumulativeString == rule.openTag {
					openString.append(char)
					cumulativeString = ""
					openTagFound = true
				} else if cumulativeString == rule.intermediateTag, openTagFound {
					intermediateString.append(cumulativeString)
					cumulativeString = ""
				} else if cumulativeString == rule.closingTag, openTagFound {
					closedString.append(char)
					cumulativeString = ""
					openTagFound = false
				}
			}
			// If we're here, it means that an escape character was found but without a corresponding
			// tag, which means it might belong to a different rule.
			// It should be added to the next group of regular characters
			
			addToken(for: .openTag)
			addToken(for: .intermediateTag)
			addToken(for: .closeTag)
			openingString.append( cumulativeString )
		}
		
		if !openingString.isEmpty {
			tokens.append(Token(type: .string, inputString: "\(openingString)"))
		}
		
		return tokens
	}
	
	func validateSpacing( nextCharacter : String?, previousCharacter : String?, with rule : CharacterRule ) -> Bool {
		switch rule.spacesAllowed {
		case .leadingSide:
			guard nextCharacter != nil else {
				return true
			}
			if nextCharacter == " "  {
				return false
			}
		case .trailingSide:
			guard previousCharacter != nil else {
				return true
			}
			if previousCharacter == " " {
				return false
			}
		case .no:
			switch (previousCharacter, nextCharacter) {
			case (nil, nil), ( " ", _ ), (  _, " " ):
				return false
			default:
				return true
			}
		
		case .oneSide:
			switch (previousCharacter, nextCharacter) {
			case  (nil, " " ), (" ", nil), (" ", " " ):
				return false
			default:
				return true
			}
		default:
			break
		}
		return true
	}
	
}
