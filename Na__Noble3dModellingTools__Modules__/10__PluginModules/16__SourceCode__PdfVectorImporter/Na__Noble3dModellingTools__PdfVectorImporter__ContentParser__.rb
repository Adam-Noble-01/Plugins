# =============================================================================
# NA NOBLE3D MODELLING TOOLS - PDF VECTOR IMPORTER - CONTENT STREAM PARSER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__PdfVectorImporter__ContentParser__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__PdfVectorImporter__ContentParser
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Tokenise a decoded PDF content stream and convert its path
#              construction operators into flattened polylines in page space.
# CREATED    : 2026
#
# DESCRIPTION:
# - Tracks the graphics-state CTM through q / Q / cm operators.
# - Interprets path operators m, l, c, v, y, re, h into device-space points.
# - Flattens cubic Bezier curves (c, v, y) into straight segments.
# - Ignores text, image, shading and colour operators.
# - Reports whether any vector path data is present in the stream.
#
# COORDINATE NOTE:
# - Output points are in PDF user-space points (1/72 inch), already transformed
#   by the CTM. PDF Y is up, which maps directly onto the SketchUp green axis.
#
# =============================================================================

require 'strscan'

module Na__Noble3dModellingTools
    module Na__PdfVectorImporter__ContentParser

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        DEFAULT_BEZIER_STEPS = 16              # Segments generated per cubic Bezier curve
        IDENTITY_MATRIX      = [1.0, 0.0, 0.0, 1.0, 0.0, 0.0].freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Entry Points
# -----------------------------------------------------------------------------

        # FUNCTION | Quick Detection of Vector Path Data in a Content String
        # ------------------------------------------------------------
        def self.Na__PdfVectorImporter__ContentHasVectorData?(content)
            return false if content.nil? || content.empty?
            !!(content =~ /[\d.]\s+(?:re|m|l|c|v|y)\b/n)               # <-- Number followed by a path operator
        end
        # ------------------------------------------------------------

        # FUNCTION | Parse a Content Stream into Page-Space Polylines
        # ------------------------------------------------------------
        def self.Na__PdfVectorImporter__ParsePolylines(content, bezier_steps = DEFAULT_BEZIER_STEPS)
            state    = na_new_state(bezier_steps)
            return { polylines: [], has_vector_data: false } if content.nil? || content.empty?

            scanner  = StringScanner.new(content)
            operands = []

            until scanner.eos?
                token = na_next_token(scanner)
                break if token.nil?

                if token[0] == :num
                    operands << token[1]
                else
                    na_apply_operator(state, token[1], operands)
                    operands = []
                end
            end

            na_finish_path(state, false)                              # <-- Flush any unpainted trailing path
            { polylines: state[:output], has_vector_data: state[:saw_path] }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Parser State
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build a Fresh Parser State Hash
        # ------------------------------------------------------------
        def self.na_new_state(bezier_steps)
            {
                ctm:        IDENTITY_MATRIX.dup,
                stack:      [],
                subpaths:   [],
                current:    [],
                cur_user:   [0.0, 0.0],
                start_user: [0.0, 0.0],
                output:     [],
                saw_path:   false,
                steps:      bezier_steps.to_i < 2 ? 2 : bezier_steps.to_i
            }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Operator Dispatch
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Apply One Content-Stream Operator
        # ------------------------------------------------------------
        def self.na_apply_operator(state, operator, operands)
            case operator
            when 'q'
                state[:stack].push(state[:ctm].dup)
            when 'Q'
                state[:ctm] = state[:stack].pop || state[:ctm]
            when 'cm'
                na_apply_cm(state, operands)
            when 'm'
                na_apply_moveto(state, operands)
            when 'l'
                na_apply_lineto(state, operands)
            when 'c'
                na_apply_curve_c(state, operands)
            when 'v'
                na_apply_curve_v(state, operands)
            when 'y'
                na_apply_curve_y(state, operands)
            when 're'
                na_apply_rectangle(state, operands)
            when 'h'
                na_close_subpath(state)
            when 's', 'b', 'b*'
                na_finish_path(state, true)                           # <-- Close current subpath, then paint
            when 'S', 'f', 'F', 'B', 'f*', 'B*'
                na_finish_path(state, false)                          # <-- Paint (stroke / fill) the path
            when 'n'
                na_discard_path(state)                                # <-- End path with no painting (e.g. clip-only)
            when 'W', 'W*'
                # Clip operator - geometry retained until the following painting / end op
            else
                # All other operators (text, colour, image, state) are ignored
            end
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Path Construction Operators
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Concatenate a cm Transformation Matrix onto the CTM
        # ------------------------------------------------------------
        def self.na_apply_cm(state, operands)
            return if operands.length < 6
            state[:ctm] = na_mat_mul(operands.last(6), state[:ctm])
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Begin a New Subpath (moveto)
        # ------------------------------------------------------------
        def self.na_apply_moveto(state, operands)
            return if operands.length < 2
            x, y = operands.last(2)
            na_flush_subpath(state)
            state[:cur_user]   = [x, y]
            state[:start_user] = [x, y]
            state[:current]    = [na_xform(state[:ctm], x, y)]
            state[:saw_path]   = true
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Append a Straight Segment (lineto)
        # ------------------------------------------------------------
        def self.na_apply_lineto(state, operands)
            return if operands.length < 2
            x, y = operands.last(2)
            state[:current] << na_xform(state[:ctm], x, y) unless state[:current].empty?
            state[:current] = [na_xform(state[:ctm], x, y)] if state[:current].empty?
            state[:cur_user] = [x, y]
            state[:saw_path] = true
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Cubic Bezier with Two Explicit Control Points (c)
        # ------------------------------------------------------------
        def self.na_apply_curve_c(state, operands)
            return if operands.length < 6
            x1, y1, x2, y2, x3, y3 = operands.last(6)
            na_append_bezier(state, [x1, y1], [x2, y2], [x3, y3])
            state[:saw_path] = true
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Cubic Bezier Using Current Point as First Control (v)
        # ------------------------------------------------------------
        def self.na_apply_curve_v(state, operands)
            return if operands.length < 4
            x2, y2, x3, y3 = operands.last(4)
            na_append_bezier(state, state[:cur_user], [x2, y2], [x3, y3])
            state[:saw_path] = true
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Cubic Bezier Using Endpoint as Second Control (y)
        # ------------------------------------------------------------
        def self.na_apply_curve_y(state, operands)
            return if operands.length < 4
            x1, y1, x3, y3 = operands.last(4)
            na_append_bezier(state, [x1, y1], [x3, y3], [x3, y3])
            state[:saw_path] = true
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Append a Closed Rectangle Subpath (re)
        # ------------------------------------------------------------
        def self.na_apply_rectangle(state, operands)
            return if operands.length < 4
            x, y, w, h = operands.last(4)
            na_flush_subpath(state)
            rectangle = [[x, y], [x + w, y], [x + w, y + h], [x, y + h], [x, y]].map do |px, py|
                na_xform(state[:ctm], px, py)
            end
            state[:subpaths] << rectangle
            state[:cur_user]   = [x, y]
            state[:start_user] = [x, y]
            state[:current]    = []
            state[:saw_path]   = true
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Close the Current Subpath Back to its Start (h)
        # ------------------------------------------------------------
        def self.na_close_subpath(state)
            return if state[:current].empty?
            start_point = na_xform(state[:ctm], state[:start_user][0], state[:start_user][1])
            state[:current] << start_point
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Path Flushing
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Move the Building Subpath into the Completed Set
        # ------------------------------------------------------------
        def self.na_flush_subpath(state)
            state[:subpaths] << state[:current] if state[:current].length >= 2
            state[:current] = []
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Finish the Current Path and Emit its Subpaths
        # ------------------------------------------------------------
        def self.na_finish_path(state, close_first)
            na_close_subpath(state) if close_first
            na_flush_subpath(state)
            state[:output].concat(state[:subpaths]) unless state[:subpaths].empty?
            state[:subpaths] = []
            state[:current]  = []
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Discard the Current Path Without Emitting Geometry
        # ------------------------------------------------------------
        def self.na_discard_path(state)
            state[:subpaths] = []
            state[:current]  = []
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Geometry Maths
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Flatten a Cubic Bezier into Straight Segments
        # ------------------------------------------------------------
        def self.na_append_bezier(state, control_one, control_two, end_point)
            p0 = na_xform(state[:ctm], state[:cur_user][0], state[:cur_user][1])
            p1 = na_xform(state[:ctm], control_one[0], control_one[1])
            p2 = na_xform(state[:ctm], control_two[0], control_two[1])
            p3 = na_xform(state[:ctm], end_point[0], end_point[1])

            state[:current] = [p0] if state[:current].empty?
            steps = state[:steps]

            (1..steps).each do |index|
                t  = index.to_f / steps
                mt = 1.0 - t
                a  = mt * mt * mt
                b  = 3.0 * mt * mt * t
                c  = 3.0 * mt * t * t
                d  = t * t * t
                x  = (a * p0[0]) + (b * p1[0]) + (c * p2[0]) + (d * p3[0])
                y  = (a * p0[1]) + (b * p1[1]) + (c * p2[1]) + (d * p3[1])
                state[:current] << [x, y]
            end

            state[:cur_user] = [end_point[0], end_point[1]]
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Apply a 2x3 Affine Matrix to a Point
        # ------------------------------------------------------------
        def self.na_xform(matrix, x, y)
            [
                (matrix[0] * x) + (matrix[2] * y) + matrix[4],
                (matrix[1] * x) + (matrix[3] * y) + matrix[5]
            ]
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Multiply Two PDF Matrices (apply m1, then m2)
        # ------------------------------------------------------------
        def self.na_mat_mul(m1, m2)
            a1, b1, c1, d1, e1, f1 = m1
            a2, b2, c2, d2, e2, f2 = m2
            [
                (a2 * a1) + (c2 * b1),
                (b2 * a1) + (d2 * b1),
                (a2 * c1) + (c2 * d1),
                (b2 * c1) + (d2 * d1),
                (a2 * e1) + (c2 * f1) + e2,
                (b2 * e1) + (d2 * f1) + f2
            ]
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Tokeniser
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Return the Next Number or Operator Token
        # ------------------------------------------------------------
        def self.na_next_token(scanner)
            loop do
                scanner.skip(/[\s\x00]+/n)
                return nil if scanner.eos?

                char = scanner.peek(1)
                if char == '%'
                    scanner.skip(/%[^\r\n]*/n)
                elsif char == '('
                    na_skip_string(scanner)
                elsif char == '<'
                    if scanner.peek(2) == '<'
                        na_skip_dictionary(scanner)
                    else
                        scanner.skip(/<[^>]*>?/n)
                    end
                elsif char == '/'
                    scanner.skip(/\/[^\s\x00()<>\[\]{}\/%]*/n)
                elsif '[]{}>)'.include?(char)
                    scanner.getch
                else
                    number = scanner.scan(/[+-]?(?:\d+\.?\d*|\.\d+)/n)
                    return [:num, number.to_f] if number

                    operator = scanner.scan(/[A-Za-z'"*][A-Za-z0-9'"*]*/n)
                    if operator
                        if operator == 'BI'
                            na_skip_inline_image(scanner)
                        else
                            return [:op, operator]
                        end
                    else
                        scanner.getch                                 # <-- Consume stray byte to avoid stalling
                    end
                end
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Skip a Literal String "( ... )" with Nesting
        # ------------------------------------------------------------
        def self.na_skip_string(scanner)
            scanner.getch                                             # consume '('
            depth = 1
            until scanner.eos? || depth.zero?
                char = scanner.getch
                if char == '\\'
                    scanner.getch                                     # skip escaped character
                elsif char == '('
                    depth += 1
                elsif char == ')'
                    depth -= 1
                end
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Skip a Dictionary "<< ... >>" with Nesting
        # ------------------------------------------------------------
        def self.na_skip_dictionary(scanner)
            scanner.scan(/<</n)
            depth = 1
            until scanner.eos? || depth.zero?
                if scanner.scan(/<</n)
                    depth += 1
                elsif scanner.scan(/>>/n)
                    depth -= 1
                else
                    scanner.getch
                end
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Skip Inline Image Data (BI ... ID ... EI)
        # ------------------------------------------------------------
        def self.na_skip_inline_image(scanner)
            scanner.scan_until(/\bID/n)
            scanner.getch                                             # single whitespace after ID
            return if scanner.scan_until(/[\s\x00]EI(?=[\s\x00]|\z)/n)
            scanner.scan_until(/EI/n) || scanner.terminate
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__PdfVectorImporter__ContentParser
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
