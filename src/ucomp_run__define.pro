; docformat = 'rst'


;= API

;+
; Create an inventory of the raw files for a run.
;
; :Params:
;   raw_files : in, optional, type=strarr
;     raw files to inventory, default is all raw files in the `l0_dir`
;-
pro ucomp_run::make_raw_inventory, raw_files
  compile_opt strictarr

  self->getProperty, logger_name=logger_name

  raw_dir = filepath(self.date, root=self->config('raw/basedir'))

  if (n_params() eq 0L) then begin
    _raw_files = file_search(filepath('*.fts', root=raw_dir), count=n_raw_files)
  endif else begin
    n_raw_files = n_elements(raw_files)
    if (n_raw_files gt 0L) then begin
      _raw_files = filepath(raw_files, root=raw_dir)
    endif
  endelse

  mg_log, '%d raw files', n_raw_files, name=logger_name, /info
  for f = 0L, n_raw_files - 1L do begin
    file = ucomp_file(_raw_files[f])

    mg_log, '%s.%s [%s] %s', $
            file.ut_date, file.ut_time, $
            file.wave_type, $
            file.data_type, $
            name=logger_name, /debug

    ; store files by data type and wave type

    if (~(self.files)->hasKey(file.data_type)) then (self.files)[file.data_type] = hash()
    dtype_hash = (self.files)[file.data_type]

    if (~dtype_hash->hasKey(file.wave_type)) then dtype_hash[file.wave_type] = list()
    (dtype_hash)[file.wave_type]->add, file
  endfor
end


;+
; Retrieve a dark image for a given science image.
;
; :Params:
;   time : in, required, type=string
;     time of science image in UT with format "HHMMSS"
;-
function ucomp_run::get_dark, time
  compile_opt strictarr

  ; TODO: implement
end


;+
; Retrieve files after an inventory has been completed.
;
; :Returns:
;   `objarr` of `ucomp_file` objects
;
; :Keywords:
;   wave_type : in, optional, type=string
;     set to wave type of files to return: '1074', '1079', etc.; by default,
;     returns files of all wave types
;   data_type : in, optional, type=string
;     set to data type of files to return: 'sci', 'cal', etc.; by default,
;     returns files of all data_types
;   count : out, optional, type=long
;     set to a named variable to retrieve the number of files returned
;-
function ucomp_run::get_files, wave_type=wave_type, data_type=data_type, $
                               count=count
  compile_opt strictarr

  count = 0L   ; set for all the special cases that return early

  case 1 of
    n_elements(wave_type) eq 0L && n_elements(data_type) eq 0L: begin
        files_list = list()
        foreach dtype_hash, self.files, dtype do begin
          foreach wtype_list, dtype_hash, wtype do begin
            files_list->add, wtype_list, /extract
          endforeach
        endforeach
        files = files_list->toArray()
        count = files_list->count()
        obj_destroy, files_list
      end
    n_elements(wave_type) eq 0L: begin
        if (~(self.files)->hasKey(data_type)) then return, !null

        files_list = list()
        foreach wtype_list, (self.files)[data_type], wtype do begin
          files_list->add, wtype_list, /extract
        endforeach
        files = files_list->toArray()
        count = files_list->count()
        obj_destroy, files_list
      end
    n_elements(data_type) eq 0L: begin
        files_list = list()
        foreach dtype_hash, self.files, dtype do begin
          if (~dtype_hash->hasKey(wave_type)) then continue
          files_list->add, dtype_hash[wave_type], /extract
        endforeach
        files = files_list->toArray()
        count = files_list->count()
        obj_destroy, files_list
      end
    else: begin
        if (~(self.files)->hasKey(data_type)) then return, !null
        if (~((self.files)[data_type])->hasKey(wave_type)) then return, !null

        files_list = ((self.files)[data_type])[wave_type]
        files = files_list->toArray()
        count = files_list->count()
      end
  endcase

  return, files
end


;+
; Retrieve a flat image for a given science image.
;
; :Params:
;   time : in, required, type=string
;     time of science image in UT with format "HHMMSS"
;   wavelength : in, required, type=float
;     wavelength of science image in nm
;-
function ucomp_run::get_flat, time, wavelength
  compile_opt strictarr

  ; TODO: implement
end


;+
; Lock the raw directory if required and available.
;
; :Keywords:
;   is_available : out, optional, type=boolean
;     set to a named variable to retrieve whether the raw directory was
;     available, and therefore locked
;-
pro ucomp_run::lock, is_available=is_available
  compile_opt strictarr

  self->getProperty, logger_name=logger_name

  is_available = ucomp_state(self.date, run=self)
  if (is_available) then begin
    !null = ucomp_state(self.date, /lock, run=self)
    mg_log, 'locked %s', self.date, name=logger_name, /info
  endif else begin
    mg_log, '%s not available, skipping', self.date, name=logger_name, /info
  endelse
end


;+
; Unlock raw directory and, if `MARK_PROCESSED` is set, mark as processed.
;
; :Keywords:
;   mark_processed : in, optional, type=boolean
;     set to indicate that directory should be marked as processed after
;     unlocking
;-
pro ucomp_run::unlock, mark_processed=mark_processed
  compile_opt strictarr

  self->getProperty, logger_name=logger_name

  if (~ucomp_state(self.date, run=self)) then begin
    unlocked = ucomp_state(self.date, /unlock, run=self)
    mg_log, 'unlocked %s', self.date, name=logger_name, /info
    if (keyword_set(mark_processed)) then begin
      processed = ucomp_state(self.date, /processed, run=self)
      mg_log, 'marked %s as processed', self.date, name=logger_name, /info
    endif
  endif
end


;= performance monitoring API

;+
; Start profiler.
;-
pro ucomp_run::start_profiler
  compile_opt strictarr

  if (~self->config('engineering/profile')) then return

  ; resolve all routines
  skip_files = ['mg_log_common', 'ucomp_run__define']

  subdirs = ['gen', 'lib', 'src', 'ssw']
  top_dir = filepath('', subdir=['..'], root=mg_src_root())
  for d = 0L, n_elements(subdirs) - 1L do begin
    files = file_search(filepath(subdirs[d], root=top_dir), $
                        '*.pro', $
                        count=n_files)
    routines = file_basename(files, '.pro')

    for r = 0L, n_files - 1L do begin
      !null = where(routines[r] eq skip_files, n_matched)
      if (n_matched eq 0L) then begin
        mg_resolve_routine, routines[r], $
                            /either, /compile_full_file, /no_recompile
      endif
    endfor
  endfor

  ; start profiling routines
  profiler, /system
  profiler
end


;+
; Report profiling output.
;-
pro ucomp_run::report_profiling
  compile_opt strictarr

  if (~self->config('engineering/profile')) then return

  ; quit if no place to put profile results
  engineering_basedir = self->config('engineering/basedir')
  if (n_elements(engineering_basedir) eq 0L) then begin
    mg_log, 'no engineering/basedir to save profiling', $
            name=self.logger_name, /warn
    return
  endif

  ; if needed, create engineering directory
  eng_dir = filepath('', $
                     subdir=ucomp_decompose_date(self.date), $
                     root=engineering_basedir)
  if (~file_test(eng_dir, /directory)) then begin
    file_mkdir, eng_dir
    self->getProperty, logger_name=logger_name
    ucomp_fix_permissions, eng_dir, /directory, logger_name=logger_name
  endif

  basename = string(self.date, format='(%"%s.ucomp.profiler.csv")')
  filename = filepath(basename, root=eng_dir)
    
  mg_profiler_report, filename=filename, /csv
end


;+
; :Returns:
;   clock identifier structure with fields `name` (string) and `time` (double)
;
; :Params:
;   routine_name : in, required, type=string
;     name of routine being timed
;-
function ucomp_run::start, routine_name
  compile_opt strictarr

  if (self.calls->hasKey(routine_name)) then begin
    (self.calls)[routine_name] += 1
  endif else begin
    (self.calls)[routine_name] = 1
  endelse
  
  return, tic(routine_name)
end


;+
; Call to indicate the routine with the corresponding `clock_id` is done,
; returning the total time of the execution.
;
; :Returns:
;   float
;
; :Params:
;   clock_id : in, required, type=structure
;     clock identifier from `::start`
;-
function ucomp_run::stop, clock_id
  compile_opt strictarr

  time = toc(clock_id)

  if (self.times->hasKey(clock_id.name)) then begin
    (self.times)[clock_id.name] += time
  endif else begin
    (self.times)[clock_id.name] = time
  endelse

  return, time
end


;+
; Write the performance log.
;-
pro ucomp_run::report
  compile_opt strictarr

  ; if needed, create engineering directory 
  eng_dir = filepath('', $
                     subdir=ucomp_decompose_date(self.date), $
                     root=self->config('engineering/basedir'))
  if (~file_test(eng_dir, /directory)) then begin
    file_mkdir, eng_dir
    self->getProperty, logger_name=logger_name
    ucomp_fix_permissions, eng_dir, /directory, logger_name=logger_name
  endif

  basename = string(self.date, format='(%"%s.ucomp.perf.txt")')
  filename = filepath(basename, root=eng_dir)

  openw, lun, filename, /get_lun

  widths = [35, 32, 10, 10]
  printf, lun, 'routine name', 'total time', '# calls', 'secs/call', $
          format=mg_format('%*s %*s %*s %*s', widths)
  printf, lun, mg_repstr('-', widths), format='(%"%s %s %s %s")'
  foreach n_calls, self.calls, routine_name do begin
    if (self.times->hasKey(routine_name)) then begin
      time = (self.times)[routine_name]
    endif else begin
      time = !values.f_nan
    endelse

    if (finite(time)) then begin
      time_str = ucomp_sec2str(time)
      mean_time = time / n_calls
    endif else begin
      mean_time = !values.f_nan
      time_str = 'NaN'
    endelse

    printf, lun, routine_name, time_str, n_calls, mean_time, $
            format=mg_format('%-*s %*s %*d %*.3f', widths)
  endforeach

  free_lun, lun
end


;= epoch values

;+
; Retrieve the epoch value for a given option name.
;
; :Returns:
;   any
;
; :Params:
;   option_name : in, required, type=string
;     name of an epoch option
;
; :Keywords:
;   datetime : in, optional, type=string
;     datetime in the form 'YYYYMMDD' or 'YYYYMMDD.HHMMSS'; defaults to the
;     value of the `DATETIME` property if this keyword is not given
;-
function ucomp_run::epoch, option_name, datetime=datetime
  compile_opt strictarr
  on_error, 2

  value = self.epochs->get(option_name, datetime=datetime)

  return, value
end


;+
; Retrieve the value for a given option name for a given line.
;
; :Returns:
;   any
;
; :Params:
;   line : in, required, type=string
;     line name, e.g., '1074'
;   option_name : in, required, type=string
;     name of an epoch option, e.g., 'center_wavelength'
;-
function ucomp_run::line, line, option_name
  compile_opt strictarr

  value = self.lines->get(option_name, section=line, found=found)
  return, value
end


;= config values

;+
; Get a config file value.
;
; :Returns:
;   value of the correct type
;
; :Params:
;   name : in, required, type=string
;     section and option name in the form "section/option"
;-
function ucomp_run::config, name
  compile_opt strictarr
  on_error, 2

  tokens = strsplit(name, '/', /extract, count=n_tokens)
  if (n_tokens ne 2) then message, 'bad format for config option name'

  value = self.options->get(tokens[1], section=tokens[0], found=found)

  if (name eq 'raw/basedir' && n_elements(value) eq 0L) then begin
    routing_file = self.options->get('routing_file', section='raw')
    value = ucomp_get_route(routing_file, self.date)
  endif

  return, value
end


;= property access

;+
; Get properties.
;-
pro ucomp_run::getProperty, date=date, $
                            mode=mode, $
                            logger_name=logger_name, $
                            config_contents=config_contents, $
                            all_wave_types=all_wave_types, $
                            t0=t0
  compile_opt strictarr
  on_error, 2

  if (arg_present(date)) then date = self.date
  if (arg_present(mode)) then mode = self.mode

  if (arg_present(logger_name)) then begin
    logger_name = string(self.mode, format='(%"ucomp/%s")')
  endif

  if (arg_present(config_contents)) then begin
    config_contents = reform(self.options->_toString(/substitute))
  endif

  if (arg_present(all_wave_types)) then begin
    wtype_hash = hash()
    foreach dtype_hash, self.files, dtype do begin
      foreach wtype_list, dtype_hash, wtype do begin
        wtype_hash[wtype] = 1B
      endforeach
    endforeach
    all_wave_types = (wtype_hash->keys())->toArray()
    obj_destroy, wtype_hash
  endif

  if (arg_present(t0)) then t0 = self.t0
end


;+
; Set properties.
;-
pro ucomp_run::setProperty, datetime=datetime, $
                            t0=t0
  compile_opt strictarr
  on_error, 2

  if (n_elements(datetime) gt 0L) then self.epochs->setProperty, datetime=datetime
  if (n_elements(t0) gt 0L) then self.t0 = t0
end


;= overload operators

function ucomp_run::_overloadPrint
  compile_opt strictarr

  return, transpose(['UCoMP run', $
                    '  date: ' + self.date, $
                    '  mode: ' + self.mode])
end

function ucomp_run::_overloadHelp, varname
  compile_opt strictarr

  type = 'UCoMP run'
  specs = string(self.date, format='(%"%s")')
  return, string(varname, type, specs, format='(%"%-15s %-9s = <%s>")')
end


;= initialization


;+
; Rotate logs and use config file values to setup the logger.
;-
pro ucomp_run::_setup_logger
  compile_opt strictarr
  on_error, 2

  ; log message formats

  fmt = '%(time)s %(levelshortname)s: %(routine)s: %(message)s'
  if (self->config('logging/include_pid')) then fmt = '[%(pid)s] ' + fmt
  time_fmt = '(C(CYI4, CMOI2.2, CDI2.2, "." CHI2.2, CMI2.2, CSI2.2))'

  ; get logging values from config file
  log_dir     = self->config('logging/dir')
  level_name  = self->config('logging/level')
  max_version = self->config('logging/max_version')
  max_width   = self->config('logging/max_width')

  ; setup log directory and file
  basename = string(self.date, self.mode, format='(%"%s.ucomp.%s.log")')
  filename = filepath(basename, root=log_dir)
  if (~file_test(log_dir, /directory)) then begin
    file_mkdir, log_dir
    self->getProperty, logger_name=logger_name
    ucomp_fix_permissions, log_dir, /directory, logger_name=logger_name
  endif

  ; rotate logs
  if (self.mode ne 'realtime') then begin
    mg_rotate_log, filename, max_version=max_version
  endif

  ; configure logger
  self->getProperty, logger_name=logger_name
  mg_log, name=logger_name, logger=logger
  logger->setProperty, format=fmt, $
                       time_format=time_fmt, $
                       max_width=max_width, $
                       level=mg_log_name2level(level_name), $
                       filename=filename
end


;= lifecycle methods

;+
; Free resources.
;-
pro ucomp_run::cleanup
  compile_opt strictarr

  obj_destroy, [self.options, self.epochs, self.lines]

  ; performance monitoring API
  obj_destroy, [self.calls, self.times]

  foreach wave_type, self.files do begin
    foreach file, wave_type do obj_destroy, file
    obj_destroy, wave_type
  endforeach
  obj_destroy, self.files
end


;+
; Initialize the run.
;
; :Params:
;   date : in, required, type=string
;     observing date in the form 'YYYYMMDD'; this is the local HST date of the
;     observations, i.e., it does not change at midnight UT during the middle of
;     an observing day
;   mode : in, required, type=string
;     mode, i.e., either 'realtime' or 'eod'
;   config_filename : in, required, type=string
;     filename of config file specifying the run
;
; :Keywords:
;   no_log : in, optional, type=boolean
;     set to not initialize the logs
;-
function ucomp_run::init, date, mode, config_filename, no_log=no_log
  compile_opt strictarr

  self.date = date
  self.mode = mode

  self->getProperty, logger_name=logger_name

  ; setup config options
  config_spec_filename = filepath('ucomp.spec.cfg', $
                                  subdir=['..', 'config'], $
                                  root=mg_src_root())

  self.options = mg_read_config(config_filename, spec=config_spec_filename)
  config_valid = self.options->is_valid(error_msg=error_msg)
  if (~config_valid) then begin
    mg_log, 'invalid configuration file', name=logger_name, /critical
    mg_log, '%s', error_msg, name=logger_name, /critical
    return, 0
  endif

  if (~keyword_set(no_log)) then self->_setup_logger

  ; setup epoch reading
  epochs_filename = filepath('epochs.cfg', root=mg_src_root())
  epochs_spec_filename = filepath('epochs.spec.cfg', root=mg_src_root())

  self.epochs = mgffepochparser(epochs_filename, epochs_spec_filename)
  epochs_valid = self.epochs->is_valid(error_msg=error_msg)
  if (~epochs_valid) then begin
    mg_log, 'invalid epochs file', name=logger_name, /critical
    mg_log, '%s', error_msg, name=logger_name, /critical
    return, 0
  endif

  ; setup information about lines
  lines_filename = filepath('lines.cfg', root=mg_src_root())
  lines_spec_filename = filepath('lines.spec.cfg', root=mg_src_root())

  self.lines = mg_read_config(lines_filename, spec=lines_spec_filename)
  lines_valid = self.lines->is_valid(error_msg=error_msg)
  if (~lines_valid) then begin
    mg_log, 'invalid lines file', name=logger_name, /critical
    mg_log, '%s', error_msg, name=logger_name, /critical
    return, 0
  endif

  self.files = hash()   ; wave_type (string) -> list of file objects

  ; performance monitoring
  self.calls = orderedhash()   ; routine name (string) -> # of calls (long)
  self.times = hash()   ; routine name (string) -> times (float) in seconds

  return, 1
end


;+
; Define the data in the run class.
;-
pro ucomp_run__define
  compile_opt strictarr

  !null = {ucomp_run, inherits IDL_Object, $
           date:    '', $
           mode:    '', $          ; eod, realtime, cal
           t0:      0.0D, $
           options: obj_new(), $
           epochs:  obj_new(), $
           lines:   obj_new(), $
           files:   obj_new(), $

           ; performance
           calls:   obj_new(), $
           times:   obj_new()}
end
