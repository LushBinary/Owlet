//
//  OwletSymbol.swift
//  Owlet
//
//  Generates the menu-bar glyph in code (no external asset needed): a friendly
//  line-art owl perched on a branch — a rounded body with two ear tufts, two big
//  round eyes with happy closed-eye smiles, a small beak, a curved chest, and
//  two little feet gripping a twig. Rendered as a *template* image so macOS
//  tints it for the light/dark menu bar: a clean outline when idle, a bold
//  filled owl when active.
//

import AppKit

enum OwletSymbol {

    /// Menu-bar sized owl-on-a-branch glyph.
    /// `active` => bold filled owl; otherwise clean line art.
    static func image(active: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)

        let image = NSImage(size: size, flipped: false) { _ in
            let body   = OwlGeometry.body()
            let belly  = OwlGeometry.belly()
            let eyes   = OwlGeometry.eyes()
            let smiles = OwlGeometry.eyeSmiles()
            let beak   = OwlGeometry.beak()
            let feet   = OwlGeometry.feet()
            let branch = OwlGeometry.branch()

            if active {
                // Bold, filled owl.
                NSColor.black.set()
                body.fill()
                feet.fill()
                branch.lineWidth = 1.4
                branch.lineCapStyle = .round
                branch.stroke()

                // Punch the face line work out so it reads through the fill
                // (the menu bar shows through, like the drawn lines).
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                NSColor.black.set()
                beak.fill()
                for path in [belly, eyes, smiles] {
                    path.lineWidth = 1.05
                    path.lineJoinStyle = .round
                    path.lineCapStyle = .round
                    path.stroke()
                }
                NSGraphicsContext.current?.compositingOperation = .sourceOver
            } else {
                // Clean line art (matches the reference).
                NSColor.black.set()
                for path in [body, belly, eyes, smiles, beak, feet, branch] {
                    path.lineWidth = 1.05
                    path.lineJoinStyle = .round
                    path.lineCapStyle = .round
                    path.stroke()
                }
            }
            return true
        }

        image.isTemplate = true          // adapt to menu-bar appearance / vibrancy
        return image
    }
}

/// Shared owl artwork, defined once in an 18x18 space (origin bottom-left) so it
/// can be reused by the menu-bar glyph and the app-icon generator.
enum OwlGeometry {

    /// Rounded head/body silhouette with two pointed ear tufts.
    static func body() -> NSBezierPath {
        let p = NSBezierPath()

        p.move(to: NSPoint(x: 5.0, y: 16.4))                                    // left ear tip
        p.line(to: NSPoint(x: 6.7, y: 14.0))                                    // left ear inner base
        p.curve(to: NSPoint(x: 11.3, y: 14.0),                                  // crown arc between the ears
                controlPoint1: NSPoint(x: 7.7, y: 15.2),
                controlPoint2: NSPoint(x: 10.3, y: 15.2))
        p.line(to: NSPoint(x: 13.0, y: 16.4))                                   // right ear tip
        p.line(to: NSPoint(x: 14.2, y: 12.6))                                   // right ear outer -> head side
        p.curve(to: NSPoint(x: 14.8, y: 9.0),                                   // right upper side
                controlPoint1: NSPoint(x: 15.0, y: 11.6),
                controlPoint2: NSPoint(x: 15.0, y: 10.2))
        p.curve(to: NSPoint(x: 13.6, y: 4.2),                                   // right lower side
                controlPoint1: NSPoint(x: 14.6, y: 7.0),
                controlPoint2: NSPoint(x: 14.4, y: 5.4))
        p.curve(to: NSPoint(x: 9.0, y: 3.0),                                    // bottom right -> center
                controlPoint1: NSPoint(x: 12.6, y: 3.4),
                controlPoint2: NSPoint(x: 10.8, y: 3.0))
        p.curve(to: NSPoint(x: 4.4, y: 4.2),                                    // bottom center -> left
                controlPoint1: NSPoint(x: 7.2, y: 3.0),
                controlPoint2: NSPoint(x: 5.4, y: 3.4))
        p.curve(to: NSPoint(x: 3.2, y: 9.0),                                    // left lower side
                controlPoint1: NSPoint(x: 3.6, y: 5.4),
                controlPoint2: NSPoint(x: 3.4, y: 7.0))
        p.curve(to: NSPoint(x: 3.8, y: 12.6),                                   // left upper side
                controlPoint1: NSPoint(x: 3.0, y: 10.2),
                controlPoint2: NSPoint(x: 3.0, y: 11.6))
        p.line(to: NSPoint(x: 5.0, y: 16.4))                                    // head side -> left ear tip
        p.close()

        return p
    }

    /// Two big round eyes that meet in the middle of the face.
    static func eyes() -> NSBezierPath {
        let r: CGFloat = 1.95
        let cy: CGFloat = 11.7
        let p = NSBezierPath()
        p.appendOval(in: NSRect(x: 7.4 - r, y: cy - r, width: r * 2, height: r * 2))   // left eye
        p.appendOval(in: NSRect(x: 10.6 - r, y: cy - r, width: r * 2, height: r * 2))  // right eye
        return p
    }

    /// Happy closed-eye "smiles" (shallow upward arcs) inside each eye.
    static func eyeSmiles() -> NSBezierPath {
        let cy: CGFloat = 11.6
        let p = NSBezierPath()
        for cx in [CGFloat(7.4), CGFloat(10.6)] {
            p.move(to: NSPoint(x: cx - 0.9, y: cy + 0.15))
            p.curve(to: NSPoint(x: cx + 0.9, y: cy + 0.15),
                    controlPoint1: NSPoint(x: cx - 0.35, y: cy - 0.75),
                    controlPoint2: NSPoint(x: cx + 0.35, y: cy - 0.75))
        }
        return p
    }

    /// Small downward beak triangle just below the eyes.
    static func beak() -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 8.3, y: 9.5))
        p.line(to: NSPoint(x: 9.7, y: 9.5))
        p.line(to: NSPoint(x: 9.0, y: 8.0))
        p.close()
        return p
    }

    /// The chest / belly: an open U suggesting the front and folded wings.
    static func belly() -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 6.5, y: 9.8))
        p.curve(to: NSPoint(x: 9.0, y: 4.7),
                controlPoint1: NSPoint(x: 6.2, y: 6.6),
                controlPoint2: NSPoint(x: 7.5, y: 4.7))
        p.curve(to: NSPoint(x: 11.5, y: 9.8),
                controlPoint1: NSPoint(x: 10.5, y: 4.7),
                controlPoint2: NSPoint(x: 11.8, y: 6.6))
        return p
    }

    /// Two little feet gripping the branch.
    static func feet() -> NSBezierPath {
        let p = NSBezierPath()
        p.appendOval(in: NSRect(x: 7.35, y: 2.35, width: 1.3, height: 1.25))
        p.appendOval(in: NSRect(x: 9.35, y: 2.35, width: 1.3, height: 1.25))
        return p
    }

    /// The perch: a horizontal branch with a small twig on the left.
    static func branch() -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 3.2, y: 2.4))
        p.line(to: NSPoint(x: 14.8, y: 2.4))
        p.move(to: NSPoint(x: 5.4, y: 2.4))                                     // twig
        p.line(to: NSPoint(x: 3.4, y: 1.2))
        return p
    }
}
