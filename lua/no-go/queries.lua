local M = {}

M.error_query = [[
(
  (if_statement
    condition: (binary_expression
      left: (identifier) @err_identifier)
    consequence: (block
      (statement_list
        (return_statement
          (expression_list
            (identifier) @return_identifier)?)))) @collapse_block) @if_statement
]]

M.import_query = [[
  (import_declaration 
    (import_spec_list 
      (import_spec 
        path: (interpreted_string_literal 
          (interpreted_string_literal_content))) 
      (import_spec 
        path: (interpreted_string_literal 
          (interpreted_string_literal_content)))) @collapse_block) @import_statement 
]]

return M
