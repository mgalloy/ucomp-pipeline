; docformat = 'rst'

function ucomp_validate_l0_file_checkspec, keyword_name, specline, $
                                           keyword_value, n_found, $
                                           error_msg=error_msg
  compile_opt strictarr

  required = 0B
  type     = 0L
  value    = !null
  values   = !null

  if (size(keyword_value, /type) eq 7) then begin
    keyword_value = strtrim(keyword_value, 2)
  endif

  tokens = strtrim(strsplit(specline, ',', /extract, count=n_tokens), 2)
  for t = 0L, n_tokens - 1L do begin
    parts = strsplit(tokens[t], '=', /extract, count=n_parts)
    case parts[0] of
      'required': required = 1B
      'value': value = parts[1]
      'values': begin
          values = strsplit(strmid(parts[1], 1, strlen(parts[1]) - 2), $
                            '|', $
                            /extract, $
                            count=n_values)
        end
      'type': begin
          case strlowcase(parts[1]) of
            'boolean': type = 1
            'int': type = 3
            'float': type = 5
            'str': type = 7
          endcase
        end
    endcase
  endfor

  if (n_elements(value) gt 0L) then begin
    if (type eq 1) then begin
      value = byte(long(value))
    endif else value = fix(value, type=type)
  endif

  if (n_elements(values) gt 0L) then values = fix(values, type=type)

  if ((n_found eq 0) && (required eq 0B)) then return, 1B

  keyword_type = size(keyword_value, /type)
  ;if (keyword_type ne type) then begin
  ;  error_msg = string(keyword_type, type, $
  ;                     format='(%"type of keyword (%d) not spec type (%d)")')
  ;  return, 0B
  ;endif

  if (n_elements(value) gt 0L) then begin
    if (n_found eq 0L) then begin
      error_msg = string(keyword_name, format='(%"%s: no value")')
      return, 0B
    endif else begin
      if (keyword_value ne value) then begin
        error_msg = string(keyword_value, format='(%"wrong value: %s")')
        return, 0B
      endif
    endelse
  endif

  if (n_elements(values) gt 0L) then begin
    if (n_found eq 0L) then begin
      error_msg = string(keyword_name, format='(%"%s: no value")')
      return, 0B
    endif else begin
      ind = where(keyword_value eq values, count)
      if (count ne 1L) then begin
        error_msg = string(keyword_value, format='(%"not one of possible values: %s")')
        return, 0B
      endif
    endelse
  endif

  return, 1B
end


function ucomp_validate_l0_file_checkheader, header, spec, $
                                             extension=extension, $
                                             error_list=error_list
  compile_opt strictarr

  type = n_elements(extension) eq 0L ? 'primary' : 'extension'

  case type of
    'primary': location = 'primary header'
    'extension': location = string(extension, format='(%"ext %d header")')
  endcase

  is_valid = 1B

  keywords = mg_fits_keywords(header, count=n_keywords)
  spec_keywords = spec->options(section=type, count=n_spec_keywords)

  if (n_keywords gt n_spec_keywords) then begin
    error_msg = string(n_keywords, n_spec_keywords, $
                       format='(%"more keywords (%d) than spec (%d)")')
    is_valid = 0B
  endif

  for k = 0L, n_spec_keywords - 1L do begin
    specline = spec->get(spec_keywords[k], section=type)
    value = sxpar(header, spec_keywords[k], count=n_found)
    is_valid = ucomp_validate_l0_file_checkspec(spec_keywords[k], $
                                                specline, value, n_found, $
                                                error_msg=error_msg)
    if (~is_valid) then begin
      error_list->add, string(location, spec_keywords[k], error_msg, $
                              format='(%"%s: %s: %s")')
      is_valid = 0B
    endif
  endfor

  for k = 0L, n_keywords - 1L do begin
    value = spec->get(keywords[k], section=type, found=found)
    if (~found) then begin
      error_list->add, string(location, keywords[k], $
                              format='(%"%s: keyword %s not found in spec")')
      is_valid = 0B
    endif
  endfor

  return, is_valid
end


function ucomp_validate_l0_file_checkdata, data, spec, $
                                           n_extensions=n_extensions, $
                                           error_list=error_list
  compile_opt strictarr

  is_valid = 1B

  ext_type = n_elements(n_extensions) eq 0L ? 'primary' : 'extension'
  section = string(ext_type, format='(%"%s-data")')

  data_type = size(data, /type)
  spec_type = spec->get('type', section=section, type=3)

  if (data_type ne spec_type) then begin
    error_list->add, string(ext_type, data_type, spec_type, $
                            format='(%"%s data: wrong type for data: %d (spec: %d)")')
    is_valid = 0B
  endif

  ; if extension data, remove n_extensions from end
  data_n_dims = size(data, /n_dimensions) - (n_elements(n_extensions) gt 0L)
  spec_n_dims = spec->get('n_dims', section=section)

  if (data_n_dims ne spec_n_dims) then begin
    error_list->add, string(ext_type, data_n_dims, spec_n_dims, $
                            format='(%"%s data: wrong number of dims for data: %d (spec: %s)")')
    is_valid = 0B
  endif

  if (n_elements(n_extensions) gt 0L) then begin
    data_dims = size(data, /dimensions)
    for d = 0L, data_n_dims - 1L do begin
      spec_dim = spec->get(string(d, format='(%"dim%d")'), section=section, type=3)
      if (data_dims[d] ne spec_dim) then begin
        error_list->add, string(ext_type, d, data_dims[d], spec_dim, $
                                format='(%"%s data: wrong size for data dim %d, %d (spec: %d)")')
        is_valid = 0B
      endif
    endfor
  endif

  return, is_valid
end


;+
; Validate an L0 file against the specification.
;
; :Returns:
;   1 if valid, 0 if not
;
; :Params:
;   filename : in, required, type=string
;     L0 file to validate
;   validation_spec : in, required, type=string
;     filename of the specification of L0 keyword format
;
; :Keywords:
;   error_msg : out, optional, type=string
;     set to a named variable to retrieve the problem with the file (at least
;     the first problem encountered), empty string if no problem
;-
function ucomp_validate_l0_file, filename, validation_spec, $
                                 error_msg=error_msg
  compile_opt strictarr

  error_list = list()
  error_msg = ''
  is_valid = 1B

  catch, error
  if (error ne 0L) then begin
    catch, /cancel
    error_list->add, !error_state.msg
    is_valid = 0B
    goto, done
  endif

  if (~file_test(filename, /regular)) then begin
    error_list->add, 'file does not exist'
    is_valid = 0B
    goto, done
  endif

  ucomp_read_raw_data, filename, $
                       primary_data=primary_data, $
                       primary_header=primary_header, $
                       ext_data=ext_data, $
                       ext_headers=ext_headers, $
                       n_extensions=n_extensions

  l0_spec = mg_read_config(validation_spec)

  ; check primary data
  is_valid = ucomp_validate_l0_file_checkdata(primary_data, l0_spec, $
                                              error_list=error_list)

  ; check primary header against header spec
  is_valid = ucomp_validate_l0_file_checkheader(primary_header, $
                                                l0_spec, $
                                                error_list=error_list)

  ; check extension data
  is_valid = ucomp_validate_l0_file_checkdata(ext_data, l0_spec, $
                                              n_extensions=n_extensions, $
                                              error_list=error_list)

  ; check extensions
  for e = 1, n_extensions do begin
    ; check ext header against spec
    is_valid = ucomp_validate_l0_file_checkheader(ext_headers[e - 1], $
                                                  l0_spec, $
                                                  extension=e, $
                                                  error_list=error_list)
  endfor

  done:

  error_msg = error_list->toArray()

  ; cleanup
  if (obj_valid(l0_header_spec)) then obj_destroy, l0_header_spec
  if (obj_valid(ext_headers)) then obj_destroy, ext_headers
  if (obj_valid(error_list)) then obj_destroy, error_list

  return, is_valid
end


; main-level example program

raw_basedir = '/hao/twilight/Data/UCoMP/raw.test'

date='20190220'

basename = '20190220.203209.ucomp.FTS'
filename = filepath(basename, $
                    subdir=[date], $
                    root=raw_basedir)

; read spec
l0_header_spec_filename = filepath('ucomp.l0.validation.cfg', $
                                   root=mg_src_root())

is_valid = ucomp_validate_l0_file(filename, l0_header_spec_filename, error_msg=error_msg)
print, is_valid ? 'Valid' : 'Not valid'
if (~is_valid) then begin
  print, transpose(error_msg)
endif

end
