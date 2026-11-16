import Foundation

/// The painted portraits a player picks from, in the rooms' order (a face is its index here;
/// static/live/overdraft.html FACES in the website repo). The images ship in the app as faces/<name>.webp.
public enum Faces {
    public static let names = [
        "owl", "wolf", "stag", "bear", "hare", "raven", "boar", "lynx",
        "heron", "otter", "badger", "falcon", "ram", "toad", "moth", "pike",
        "magpie", "ibex", "crane", "marten", "adder", "bison", "swift", "chameleon",
        "retriever", "husky", "dachshund", "greyhound", "collie", "pug", "tabby", "siamese",
        "hedgehog", "squirrel", "ferret", "mouse", "turtle", "octopus", "seahorse", "koi",
        "eagle", "penguin", "flamingo", "puffin", "parrot", "axolotl", "beetle",
    ]
    public static var count: Int { names.count }
    public static func name(_ i: Int) -> String { names[((i % count) + count) % count] }
    /// "Otter", for VoiceOver.
    public static func label(_ i: Int) -> String { name(i).prefix(1).uppercased() + name(i).dropFirst() }
    /// The first face not taken, starting from a preferred one.
    public static func firstFree(preferring p: Int, taken: [Int]) -> Int? {
        let t = Set(taken)
        return (0..<count).map { (p + $0) % count }.first { !t.contains($0) }
    }
}
