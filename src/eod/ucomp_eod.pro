; docformat = 'rst'

;+
; Run the UCoMP pipeline; this is full processing (or reprocessing) for a day
; not the quicklook/realtime processing.
;
; :Params:
;   date : in, required, type=string
;     date to process in the form "YYYYMMDD"
;   config_filename : in, required, type=string
;     filename for configuration file to use
;-
pro ucomp_eod, date, config_filename
  compile_opt strictarr

  ; initialize performance metrics
  t0 = systime(/seconds)
  start_memory = memory(/current)

  orig_except = !except
  !except = 0

  mode = 'eod'
  logger_name = string(mode, format='(%"ucomp/%s")')

  ; error handler
  catch, error
  if (error ne 0) then begin
    catch, /cancel
    mg_log, /last_error, name=logger_name, /critical
    ucomp_crash_notification, run=run
    goto, done
  endif

  if (n_params() ne 2) then begin
    mg_log, 'incorrect number of arguments', name=logger_name, /critical
    goto, done
  endif

  config_fullpath = file_expand_path(config_filename)
  if (~file_test(config_fullpath, /regular)) then begin
    mg_log, 'config file %s not found', config_fullpath, $
            name=logger_name, /critical
    goto, done
  endif

  ;== initialize

  ; create run object
  run = ucomp_run(date, mode, config_fullpath)
  if (~obj_valid(run)) then begin
    mg_log, 'cannot create run object', name=logger_name, /critical
    goto, done
  endif
  run.t0 = t0
  run->start_profiler

  ; log starting up pipeline with versions
  version = ucomp_version(revision=revision, branch=branch)
  mg_log, 'ucomp-pipeline %s (%s) [%s]', version, revision, branch, $
          name=run.logger_name, /info
  mg_log, 'using IDL %s on %s', !version.release, !version.os_name, $
          name=run.logger_name, /debug

  mg_log, 'starting processing for %d...', date, name=run.logger_name, /info

  if (run->config('eod/reprocess')) then begin
    ucomp_pipeline_step, 'ucomp_reprocess_cleanup', run=run
  endif

  ; copy config file to processing dir, creating dir if needed
  process_dir = filepath(date, root=run->config('processing/basedir'))
  if (~file_test(process_dir, /directory)) then begin
    file_mkdir, process_dir
    ucomp_fix_permissions, process_dir, /directory, logger_name=run.logger_name
  endif
  file_copy, config_filename, $
             filepath(string(date, format='(%"%s.ucomp.cfg")'), $
                      root=process_dir), $
             /overwrite

  run->lock, is_available=is_available
  if (~is_available) then goto, done


  ;== level 1

  ucomp_pipeline_step, 'ucomp_make_raw_inventory', run=run
  ucomp_pipeline_step, 'ucomp_check_cal_quality', run=run

  wave_types = run->config('options/wave_types')
  for w = 0L, n_elements(wave_types) - 1L do begin
    ucomp_pipeline_step, 'ucomp_check_sci_quality', wave_types[w], run=run
    ucomp_pipeline_step, 'ucomp_make_darks', wave_types[w], run=run
    ucomp_pipeline_step, 'ucomp_make_flats', wave_types[w], run=run
    ucomp_pipeline_step, 'ucomp_l1_process', wave_types[w], run=run
    ucomp_pipeline_step, 'ucomp_check_gbu', wave_types[w], run=run
  endfor

  ucomp_l1_engineering_plots, run=run


  ;== level 2

  ; TODO: add level 2 steps


  ;== finish bookkeeping

  for w = 0L, n_elements(wave_types) - 1L do begin
    ucomp_pipeline_step, 'ucomp_db_update', wave_types[w], run=run
  endfor

  ucomp_pipeline_step, 'ucomp_l0_distribute', run=run

  ucomp_pipeline_step, 'ucomp_get_observerlog', run=run

  for w = 0L, n_elements(wave_types) - 1L do begin
    ucomp_pipeline_step, 'ucomp_l1_distribute', wave_types[w], run=run
    ucomp_pipeline_step, 'ucomp_l2_distribute', wave_types[w], run=run
  endfor

  ucomp_pipeline_step, 'ucomp_send_notification', run=run


  ;== cleanup and quit
  done:

  mg_log, /check_math, name=logger_name, /debug

  ; unlock raw directory and mark processed if no crash
  if (obj_valid(run)) then begin
    ; only unlock if this process was responsible for locking it
    if (is_available) then run->unlock, mark_processed=error eq 0

    run->report
    run->report_profiling
  endif

  t1 = systime(/seconds)
  mg_log, 'total running time: %s', ucomp_sec2str(t1 - t0), $
          name=logger_name, /info

  if (obj_valid(run)) then obj_destroy, run
  mg_log, /quit

  !except = orig_except
end
