; docformat = 'rst'

function ucomp_update_database_ut::init, _extra=e
  compile_opt strictarr

  if (~self->UCoMPutTestCase::init(_extra=e)) then return, 0

  self->addTestingRoutine, 'ucomp_update_database'

  return, 1
end


pro ucomp_update_database_ut__define
  compile_opt strictarr

  define = { ucomp_update_database_ut, inherits UCoMPutTestCase }
end
