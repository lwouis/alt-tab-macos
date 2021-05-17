//
//  HttpRouter.swift
//  Swifter
//
//  Copyright (c) 2014-2016 Damian Kołakowski. All rights reserved.
//

import Foundation

open class HttpRouter {

    public init() {}

    private class Node {

        /// The children nodes that form the route
        var nodes = [String: Node]()

        /// Define whether or not this node is the end of a route
        var isEndOfRoute: Bool = false

        /// The closure to handle the route
        var handler: ((HttpRequest) -> HttpResponse)?
    }

    private var rootNode = Node()

    /// The Queue to handle the thread safe access to the routes
    private let queue = DispatchQueue(label: "swifter.httpserverio.httprouter")

    public func routes() -> [String] {
        var routes = [String]()
        for (_, child) in rootNode.nodes {
            routes.append(contentsOf: routesForNode(child))
        }
        return routes
    }

    private func routesForNode(_ node: Node, prefix: String = "") -> [String] {
        var result = [String]()
        if node.handler != nil {
            result.append(prefix)
        }
        for (key, child) in node.nodes {
            result.append(contentsOf: routesForNode(child, prefix: prefix + "/" + key))
        }
        return result
    }

    public func register(_ method: String?, path: String, handler: ((HttpRequest) -> HttpResponse)?) {
        var pathSegments = stripQuery(path).split("/")
        if let method = method {
            pathSegments.insert(method, at: 0)
        } else {
            pathSegments.insert("*", at: 0)
        }
        var pathSegmentsGenerator = pathSegments.makeIterator()
        inflate(&rootNode, generator: &pathSegmentsGenerator).handler = handler
    }

    public func route(_ method: String?, path: String) -> ([String: String], (HttpRequest) -> HttpResponse)? {

        return queue.sync {
            if let method = method {
                let pathSegments = (method + "/" + stripQuery(path)).split("/")
                var pathSegmentsGenerator = pathSegments.makeIterator()
                var params = [String: String]()
                if let handler = findHandler(&rootNode, params: &params, generator: &pathSegmentsGenerator) {
                    return (params, handler)
                }
            }

            let pathSegments = ("*/" + stripQuery(path)).split("/")
            var pathSegmentsGenerator = pathSegments.makeIterator()
            var params = [String: String]()
            if let handler = findHandler(&rootNode, params: &params, generator: &pathSegmentsGenerator) {
                return (params, handler)
            }

            return nil
        }
    }

    private func inflate(_ node: inout Node, generator: inout IndexingIterator<[String]>) -> Node {

        var currentNode = node

        while let pathSegment = generator.next() {
            if let nextNode = currentNode.nodes[pathSegment] {
                currentNode = nextNode
            } else {
                currentNode.nodes[pathSegment] = Node()
                currentNode = currentNode.nodes[pathSegment]!
            }
        }

        currentNode.isEndOfRoute = true
        return currentNode
    }

    private func findHandler(_ node: inout Node, params: inout [String: String], generator: inout IndexingIterator<[String]>) -> ((HttpRequest) -> HttpResponse)? {

        var matchedRoutes = [Node]()
        let pattern = generator.map { $0 }
        let numberOfElements = pattern.count

        findHandler(&node, params: &params, pattern: pattern, matchedNodes: &matchedRoutes, index: 0, count: numberOfElements)
        return matchedRoutes.first?.handler
    }

    // swiftlint:disable function_parameter_count
    /// Find the handlers for a specified route
    ///
    /// - Parameters:
    ///   - node: The root node of the tree representing all the routes
    ///   - params: The parameters of the match
    ///   - pattern: The pattern or route to find in the routes tree
    ///   - matchedNodes: An array with the nodes matching the route
    ///   - index: The index of current position in the generator
    ///   - count: The number of elements if the route to match
    private func findHandler(_ node: inout Node, params: inout [String: String], pattern: [String], matchedNodes: inout [Node], index: Int, count: Int) {

        if index < count, let pathToken = pattern[index].removingPercentEncoding {

            var currentIndex = index + 1
            let variableNodes = node.nodes.filter { $0.0.first == ":" }
            if let variableNode = variableNodes.first {
                if currentIndex == count && variableNode.1.isEndOfRoute {
                    // if it's the last element of the pattern and it's a variable, stop the search and
                    // append a tail as a value for the variable.
                    let tail = pattern[currentIndex..<count].joined(separator: "/")
                    if tail.count > 0 {
                        params[variableNode.0] = pathToken + "/" + tail
                    } else {
                        params[variableNode.0] = pathToken
                    }

                    matchedNodes.append(variableNode.value)
                    return
                }
                params[variableNode.0] = pathToken
                findHandler(&node.nodes[variableNode.0]!, params: &params, pattern: pattern, matchedNodes: &matchedNodes, index: currentIndex, count: count)
            }

            if var node = node.nodes[pathToken] {
                findHandler(&node, params: &params, pattern: pattern, matchedNodes: &matchedNodes, index: currentIndex, count: count)
            }

            if var node = node.nodes["*"] {
                findHandler(&node, params: &params, pattern: pattern, matchedNodes: &matchedNodes, index: currentIndex, count: count)
            }

            if let startStarNode = node.nodes["**"] {
                let startStarNodeKeys = startStarNode.nodes.keys
                currentIndex += 1
                while currentIndex < count, let pathToken = pattern[currentIndex].removingPercentEncoding {
                    currentIndex += 1
                    if startStarNodeKeys.contains(pathToken) {
                        findHandler(&startStarNode.nodes[pathToken]!, params: &params, pattern: pattern, matchedNodes: &matchedNodes, index: currentIndex, count: count)
                    }
                }
            }
        }

        if node.isEndOfRoute && index == count {
            // if it's the last element and the path to match is done then it's a pattern matching
            matchedNodes.append(node)
            return
        }
    }

    private func stripQuery(_ path: String) -> String {
        if let path = path.components(separatedBy: "?").first {
            return path
        }
        return path
    }
}

extension String {

    func split(_ separator: Character) -> [String] {
        return self.split { $0 == separator }.map(String.init)
    }

}
