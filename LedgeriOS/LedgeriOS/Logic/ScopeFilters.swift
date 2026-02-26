import Foundation

enum ListScope {
    case project(String)   // projectId
    case inventory         // projectId == nil
    case all               // no filter
}
