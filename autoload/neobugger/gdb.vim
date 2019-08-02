if !exists("s:init")
    let s:init = 1
    " exists("*logger#getLogger")
    silent! let s:log = logger#getLogger(expand('<sfile>:t'))

    sign define GdbBreakpointEn text=● texthl=Search
    sign define GdbBreakpointDis text=● texthl=Function
    sign define GdbBreakpointDel text=● texthl=Comment

    sign define GdbCurrentLine text=☛ texthl=Error
    "sign define GdbCurrentLine text=☛ texthl=Keyword
    "sign define GdbCurrentLine text=⇒ texthl=String

    set errorformat+=#%c\ \ %.%#\ in\ %m\ \(%.%#\)\ at\ %f:%l
    set errorformat+=#%c\ \ %.%#\ in\ \ \ \ %m\ \ \ \ at\ %f:%l
    set errorformat+=#%c\ \ %m\ \(%.%#\)\ at\ %f:%l

    let s:gdb_port = 7778
    let s:breakpoint_signid_start = 5000
    let s:breakpoint_signid_max = 0

    let s:breakpoints = {}
    let s:toggle_all = 0
    let s:gdb_bt_qf = '/tmp/gdb.bt'
    let s:gdb_break_qf = '/tmp/gdb.break'
    let s:brk_file = './.gdb.break'
    let s:fl_file = './.gdb.file'
    let s:file_list = {}

    let s:module = 'gdb'
    let s:prototype = tlib#Object#New({
                \ '_class': [s:module],
                \ })
endif


" Constructor
" @param conf='local|pid|server'
"        type 'local', 'bin-exe', {'args': [list]}
"        type 'pid', 'bin-exe', {'pid': 3245}
"        type 'server', 'bin-exe', {'args': [list]}
function! neobugger#gdb#New(conf, binaryFile, args)
    let l:__func__ = substitute(expand('<sfile>'), '.*\(\.\.\|\s\)', '', '')

    let l:parent = s:prototype.New(a:0 >= 1 ? a:1 : {})
    let l:abstract = neobugger#std#New()
    call l:parent.Inherit(l:abstract)

    let gdb = l:parent
    let gdb.module = s:module
    let gdb._initialized = 0
    let gdb.args = a:args
    silent! call s:log.info(l:__func__, ": args=", string(a:args))

    let gdb._showbreakpoint = 0
    let gdb._showbacktrace = 0

    silent! call s:log.trace("Load open files ...")
    silent! call s:log.trace("  try open files from ". s:fl_file)

    " window number that will be displaying the current file
    let gdb._wid_main = win_getid()
    let gdb._jump_window = 1
    let gdb._current_buf = -1
    let gdb._current_line = -1
    let gdb._has_breakpoints = 0
    let gdb._server_exited = 0
    let gdb._gdb_bt_qf = s:gdb_bt_qf
    let gdb._gdb_break_qf = s:gdb_break_qf
    let cword = expand("<cword>")

    " Create quickfix: lgetfile, cgetfile
    if gdb._showbacktrace && win_gotoid(gdb._wid_main) == 1
        if !filereadable(gdb._gdb_bt_qf)
            exec "silent! vimgrep " . cword ." ". expand("%")
        else
            "exec "silent cgetfile " . gdb._gdb_bt_qf
        endif
        silent! copen
        let gdb._win_qf = win_getid()
    endif

    if gdb._showbreakpoint && win_gotoid(gdb._wid_main) == 1
        if !filereadable(gdb._gdb_break_qf)
            exec "silent! lvimgrep " . cword ." ". expand("%")
        else
            exec "silent lgetfile " . gdb._gdb_break_qf
        endif
        silent! lopen
        let gdb._win_lqf = win_getid()
    endif


    if win_gotoid(gdb._wid_main) == 1
        stopinsert
        call gdb.Map("nmap")
        return gdb
    else
        silent! call s:log.trace("  Cann't jump back 'main' window.")
    endif
endfunction

" @mode 0 refresh-all, 1 only-change
function! s:prototype.RefreshBreakpointSigns(mode)
    "{
    if a:mode == 0
        let i = s:breakpoint_signid_start
        while i <= s:breakpoint_signid_max
            exe 'sign unplace '.i
            let i += 1
        endwhile
    endif

    let s:breakpoint_signid_max = 0
    let id = s:breakpoint_signid_start
    for [next_key, next_val] in items(s:breakpoints)
        let buf = bufnr(next_val['file'])
        let linenr = next_val['line']

        if a:mode == 1 && next_val['change']
           \ && has_key(next_val, 'sign_id')
            exe 'sign unplace '. next_val['sign_id']
        endif

        if a:mode == 0 || (a:mode == 1 && next_val['change'])
            if next_val['state']
                exe 'sign place '.id.' name=GdbBreakpointEn line='.linenr.' buffer='.buf
            else
                exe 'sign place '.id.' name=GdbBreakpointDis line='.linenr.' buffer='.buf
            endif
            let next_val['sign_id'] = id
            let s:breakpoint_signid_max = id
            let id += 1
        endif
    endfor
    "}
endfunction


function! s:prototype.Kill()
    call self.Map("unmap")
    call self.Update_current_line_sign(0)
    exe 'bd! '. self._client_buf
    if self._server_buf != -1
        exe 'bd! '. self._server_buf
    endif
    exe 'tabnext '. self._tab
    tabclose
    neobugger#Remove(self.module)
endfunction


function! s:prototype.Send(data)
    let l:__func__ = "gdb.Send"
    silent! call s:log.trace(l:__func__. "[". string(self._client_id). "] args=". string(a:data))

    if exists("g:gdb_channel_id")
        call rpcnotify(g:gdb_channel_id, a:data)
    endif
    return

    if self._win_gdb._state.name ==# "pause" || self._win_gdb._state.name ==# "init"
        call jobsend(self._client_id, a:data."\<cr>")
    else
        silent! call s:log.error(l:__func__, ": Cann't send data when state='". self._win_gdb._state.name. "'")
    endif
endfunction


function! s:prototype._Send(data)
    let l:__func__ = "gdb._Send"
    silent! call s:log.trace(l:__func__. "() args=". string(a:data))
    call jobsend(self._client_id, a:data)
endfunction



function! s:prototype.SendSvr(data)
    let l:__func__ = "gdb.SendSvr"
    silent! call s:log.trace(l:__func__. "() args=". string(a:data))

    if has_key(self, "_server_id")
        call jobsend(self._server_id, a:data."\<cr>")
    endif
endfunction


function! s:prototype.SendJob(data)
    if has_key(self, "_job_id")
        call jobsend(self._job_id, a:data."\<cr>")
    endif
endfunction


function! s:prototype.Attach()
    if !empty(self._server_addr)
        call self.Send(printf('target remote %s',
                    \join(self._server_addr, ":")))
        call state#Switch('gdb', 'remoteconn', 0)
    endif
endfunction


function! s:prototype.Update_current_line_sign(add)
    " to avoid flicker when removing/adding the sign column(due to the change in
    " line width), we switch ids for the line sign and only remove the old line
    " sign after marking the new one
    let old_line_sign_id = get(self, '_line_sign_id', 4999)
    let self._line_sign_id = old_line_sign_id == 4999 ? 4998 : 4999
    if a:add && self._current_line != -1 && self._current_buf != -1
        exe 'sign place '. self._line_sign_id. ' name=GdbCurrentLine line='
                    \. self._current_line. ' buffer='. self._current_buf
    endif
    exe 'sign unplace '.old_line_sign_id
endfunction


" Firstly delete all breakpoints for Gdb delete breakpoints only by ref-no
" Then add breakpoints backto gdb
" @mode 0 reset-all, 1 enable-only-change, 2 delete-all
function! s:prototype.RefreshBreakpoints(mode)
    "{
    if !neobugger#Exists(s:module)
        throw 'Gdb is not running'
    endif

    let is_running = 0
    if self._win_gdb._state.name ==# "running"
        " pause first
        let is_running = 1
        call jobsend(self._client_id, "\<c-c>")
        call state#Switch('gdb', 'pause', 0)
    endif

    if a:mode == 0 || a:mode == 2
        if self._has_breakpoints
            call self.Send('delete')
            let self._has_breakpoints = 0
        endif
    endif

    if a:mode == 0 || a:mode == 1
        let is_silent = 1
        if a:mode == 1
            let is_silent = 0
        endif

        for [next_key, next_val] in items(s:breakpoints)
            if next_val['state'] && !empty(next_val['cmd'])
                if is_silent == 1
                    let is_silent = 2
                    call self.Send('silent_on')
                endif

                if a:mode == 0 || (a:mode == 1 && next_val['change'])
                    let self._has_breakpoints = 1
                    call self.Send('break '. next_val['cmd'])
                endif
            endif
        endfor
        if is_silent == 2
            call self.Send('silent_off')
        endif
    endif

    if is_running
        call self.Send('c')
    endif
    "}
endfunction


function! s:prototype.Jump(file, line)
    if !neobugger#Exists(s:module)
        throw 'Gdb is not running'
    endif
    if tabpagenr() != g:state_ctx._tab
        " Don't jump if we are not in the debugger tab
        return
    endif

    let file = a:file
    if !filereadable(file) && file[0] != '/'
        let file = '/' . file
    endif
    if !filereadable(file)
        silent! call s:log.error("Jump File not exist: " . file)
    endif


    " Method-1: Using ansync job to parse response
    "if filereadable(s:gdb_bt_qf)
    "    call delete(s:gdb_bt_qf)
    "endif
    "call self.Send('parser_bt')
    "call self.SendJob("for x in {1..15}; do if [ ! -f /tmp/gdb.bt ]; then sleep 0.2; else  echo 'jobDoneLoadBacktrace'; break; fi; done")

    "" Method-2: Using syncronize to parse response
    if self._showbacktrace && filereadable(s:gdb_bt_qf)
        exec "silent! cgetfile " . s:gdb_bt_qf
        call delete(s:gdb_bt_qf)
    endif


    let cwindow = win_getid()
    if cwindow != gdb._wid_main
        if win_gotoid(gdb._wid_main) != 1
            return
        endif
    endif
    stopinsert

    let self._current_buf = bufnr('%')
    let target_buf = bufnr(a:file, 1)
    if bufnr('%') != target_buf
        exe 'buffer ' target_buf
        let self._current_buf = target_buf
    endif
    exe ':' a:line | m'

    let fname = fnamemodify(a:file, ':p:.')
    if !has_key(s:file_list, fname)
        let s:file_list[fname] = 1
        call self.SaveVariable(s:file_list, s:fl_file)
    endif

    "let fname = fnamemodify(a:file, ':p:.')
    "exec "e ". fname
    "exec ':' a:line | m'

    let self._current_line = a:line
    if cwindow != gdb._wid_main
        call win_gotoid(cwindow)
    endif
    call self.Update_current_line_sign(1)
endfunction


function! s:prototype.Breakpoints(file)
    if !neobugger#Exists(s:module)
        throw 'Gdb is not running'
    endif
    if self._showbreakpoint && filereadable(a:file)
        exec "silent lgetfile " . a:file
    endif
endfunction


function! s:prototype.Stack(file)
    if !neobugger#Exists(s:module)
        throw 'Gdb is not running'
    endif
    if self._showbacktrace && filereadable(a:file)
        exec "silent! cgetfile " . a:file
    endif
endfunction


function! s:prototype.Interrupt()
    if !neobugger#Exists(s:module)
        throw 'Gdb is not running'
    endif
    call jobsend(self._client_id, "\<c-c>info line\<cr>")
endfunction


function! s:prototype.SaveVariable(var, file)
    call writefile([string(a:var)], a:file)
endfunction

function! s:prototype.ReadVariable(varname, file)
    let recover = readfile(a:file)[0]
    execute "let ".a:varname." = " . recover
endfunction

function! s:prototype.Breaks2Qf()
    let list2 = []
    let i = 0
    for [next_key, next_val] in items(s:breakpoints)
        if !empty(next_val['cmd'])
            let i += 1
            call add(list2, printf('#%d  %d in    %s    at %s:%d',
                        \ i, next_val['state'], next_val['cmd'],
                        \ next_val['file'], next_val['line']))
        endif
    endfor

    call writefile(split(join(list2, "\n"), "\n"), s:gdb_break_qf)
    if self._showbreakpoint && filereadable(s:gdb_break_qf)
        exec "silent lgetfile " . s:gdb_break_qf
    endif
endfunction


function! s:prototype.GetCFunLinenr()
  let lnum = line(".")
  let col = col(".")
  let linenr = search("^[^ \t#/]\\{2}.*[^:]\s*$", 'bW')
  call search("\\%" . lnum . "l" . "\\%" . col . "c")
  return linenr
endfunction


" Key: file:line, <or> file:function
" Value: empty, <or> if condition
" @state 0 disable 1 enable, Toggle: none -> enable -> disable
" @type 0 line-break, 1 function-break
function! s:prototype.ToggleBreak()
    let filenm = bufname("%")
    let linenr = line(".")
    let colnr = col(".")
    let cword = expand("<cword>")
    let cfuncline = self.GetCFunLinenr()

    let fname = fnamemodify(filenm, ':p:.')
    let type = 0
    if linenr == cfuncline
        let type = 1
        let file_breakpoints = fname .':'.cword
    else
        let file_breakpoints = fname .':'.linenr
    endif

    let mode = 0
    let old_value = get(s:breakpoints, file_breakpoints, {})
    if empty(old_value)
        let break_new = input("[break] ", file_breakpoints)
        if !empty(break_new)
            let old_value = {
                        \'file':fname,
                        \'type':type,
                        \'line':linenr, 'col':colnr,
                        \'fn' : '',
                        \'state' : 1,
                        \'cmd' : break_new,
                        \'change' : 1,
                        \}
            let mode = 1
            let s:breakpoints[file_breakpoints] = old_value
        endif
    elseif old_value['state']
        let break_new = input("[disable break] ", old_value['cmd'])
        if !empty(break_new)
            let old_value['state'] = 0
            let old_value['change'] = 1
        endif
    else
        let break_new = input("(delete break) ", old_value['cmd'])
        if !empty(break_new)
            call remove(s:breakpoints, file_breakpoints)
        endif
        let old_value = {}
    endif
    call self.SaveVariable(s:breakpoints, s:brk_file)
    call self.Breaks2Qf()
    call self.RefreshBreakpointSigns(mode)
    call self.RefreshBreakpoints(mode)
    if !empty(old_value)
        let old_value['change'] = 0
    endif
endfunction


function! s:prototype.ToggleBreakAll()
    let s:toggle_all = ! s:toggle_all
    let mode = 0
    for v in values(s:breakpoints)
        if s:toggle_all
            let v['state'] = 0
        else
            let v['state'] = 1
        endif
    endfor
    call self.RefreshBreakpointSigns(0)
    call self.RefreshBreakpoints(0)
endfunction


function! s:prototype.TBreak()
    let file_breakpoints = bufname('%') .':'. line('.')
    call self.Send("tbreak ". file_breakpoints. "\nc")
endfunction


function! s:prototype.ClearBreak()
    let s:breakpoints = {}
    call self.Breaks2Qf()
    call self.RefreshBreakpointSigns(0)
    call self.RefreshBreakpoints(2)
endfunction


function! s:prototype.FrameUp()
    call self.Send("up")
endfunction

function! s:prototype.FrameDown()
    call self.Send("down")
endfunction

function! s:prototype.Next()
    call self.Send("next")
endfunction

function! s:prototype.Step()
    call self.Send("step")
endfunction

function! s:prototype.Eval(expr)
    if !neobugger#Exists(s:module)
        throw 'Gdb is not running'
    endif

    if self._win_gdb._state.name !=# "pause"
        throw 'Gdb eval only under "pause" but state="'
                \. self._win_gdb._state.name .'"'
    endif

    "call self.Send(printf('print %s', a:expr))
    " Enable smart-eval base-on the special project
    let s:expr = a:expr
    call self.Send(printf('whatis %s', a:expr))
endfunction


" Enable smart-eval base-on the special project
function! s:prototype.Whatis(type)
    if !neobugger#Exists(s:module)
        throw 'Gdb is not running'
    endif
    if self._win_gdb._state.name !=# "pause"
        throw 'Gdb eval only under "pause" state'
    endif
    if empty(s:expr)
        throw 'Gdb eval expr is empty'
    endif

    if has_key(self, 'Symbol')
        silent! call s:log.trace("forward to getsymbol")
        let expr = self.Symbol(a:type, s:expr)
        call self.Send(expr)
    else
        call self.Send(printf('p %s', s:expr))
    endif
    let s:expr = ""
endfunction


function! s:prototype.Watch(expr)
    let expr = a:expr
    if expr[0] != '&'
        let expr = '&' . expr
    endif

    call self.Eval(expr)
    call self.Send('watch *$')
endfunction


function! s:prototype.ParseBacktrace()
  let s:lines = readfile('/tmp/gdb.bt')
  for s:line in s:lines
    echo s:line
  endfor
endfunction


function! s:prototype.ParseVar()
  let s:lines = readfile('/tmp/gdb.bt')
  for s:line in s:lines
    echo s:line
  endfor
endfunction


function! s:prototype.on_load_bt(...)
    if self._showbacktrace && filereadable(s:gdb_bt_qf)
        exec "cgetfile " . s:gdb_bt_qf
        "call utilquickfix#RelativePath()
    endif
endfunction

function! s:prototype.on_continue(...)
    call state#Switch('gdb', 'running', 0)
    call self.Update_current_line_sign(0)
endfunction

function! s:prototype.on_jump(file, line, ...)
    let l:__func__ = "gdb.on_jump"
    silent! call s:log.info(l:__func__, ' open ', a:file, ':', a:line)

    if self._win_gdb._state.name !=# "pause"
        silent! call s:log.info(gdb)
        silent! call s:log.info("State ", self._win_gdb._state.name, " => pause")
        call state#Switch('gdb', 'pause', 0)
        call self.Send('parser_bt')
        call self.Send('info line')
    endif
    call self.Jump(a:file, a:line)
endfunction

function! s:prototype.on_whatis(type, ...)
    call self.Whatis(a:type)
endfunction

function! s:prototype.on_parseend(...)
    call self.Whatis(a:type)
endfunction

function! s:prototype.on_retry(...)
    if self._server_exited
        return
    endif
    sleep 1
    call self.Attach()
    call self.Send('continue')
endfunction


function! s:prototype.on_init(...)
    let l:__func__ = "gdb.on_init"
    silent! call s:log.info(l:__func__, " args=", string(a:000))

    if self._initialized
      silent! call s:log.warn(l:__func__, "() ignore re-initial!")
      return
    endif

    let self._initialized = 1
    " set filename-display absolute
    " set remotetimeout 50
    let cmdstr = "set confirm off\n
                \ set pagination off\n
                \ set width 0\n
                \ set verbose off\n
                \ set logging off\n
                \ handle SIGUSR2 noprint nostop\n
                \ set print elements 2048\n
                \ set print pretty on\n
                \ set print array off\n
                \ set print array-indexes on\n
                \"
    call self.Send(cmdstr)

    let cmdstr = "define parser_bt\n
                \ set logging off\n
                \ set logging file /tmp/gdb.bt\n
                \ set logging overwrite on\n
                \ set logging redirect on\n
                \ set logging on\n
                \ bt\n
                \ set logging off\n
                \ echo neobugger_parseend\n
                \ end"
    call self.Send(cmdstr)

    let cmdstr = "define parser_var_bt\n
                \ set logging off\n
                \ set logging file /tmp/gdb.bt\n
                \ set logging overwrite on\n
                \ set logging redirect on\n
                \ set logging on\n
                \ bt\n
                \ set logging off\n
                \ set logging file /tmp/gdb.var\n
                \ set logging overwrite on\n
                \ set logging redirect on\n
                \ set logging on\n
                \ info local\n
                \ set logging off\n
                \ echo neobugger_parseend\n
                \ end"
    call self.Send(cmdstr)

    let cmdstr = "define silent_on\n
                \ set logging off\n
                \ set logging file /dev/null\n
                \ set logging overwrite off\n
                \ set logging redirect on\n
                \ set logging on\n
                \ end"
    call self.Send(cmdstr)

    let cmdstr = "define silent_off\n
                \ set logging off\n
                \ end"
    call self.Send(cmdstr)

    let cmdstr = "define hook-stop\n
                \ handle SIGALRM nopass\n
                \ parser_bt\n
                \ end\n
                \ \n
                \ define hook-run\n
                \ handle SIGALRM pass\n
                \ end\n
                \ \n
                \ define hook-continue\n
                \ handle SIGALRM pass\n
                \ \n
                \ end"
    call self.Send(cmdstr)

    silent! call s:log.info("Load breaks ...")
    if filereadable(s:brk_file)
        call self.ReadVariable("s:breakpoints", s:brk_file)
    endif

    silent! call s:log.info("Load set breaks ...")
    if !empty(s:breakpoints)
        call self.Breaks2Qf()
        call self.RefreshBreakpointSigns(0)
        call self.RefreshBreakpoints(0)
    endif

    if has_key(self, 'Init')
        silent! call s:log.info(l:__func__, " call Init()")
        "call neobugger#Handle(s:module, self.Init)
        call self.Init()
    else
        silent! call s:log.info(l:__func__, " Init() is null.")
    endif

    if self._autorun
        let l:cmdstr = ""
        if self._mode ==# 'local'
            let l:cmdstr = "br main\n
                        \ r"
            call self.Send(l:cmdstr)
        elseif self._mode ==# 'pid'
            let l:cmdstr = "attach ". self._attach_pid
            call self.Send(l:cmdstr)

            let l:cmdstr = "symbol-file ". self._binaryFile
            call self.Send(l:cmdstr)

            " hint backtrace
            call self.Send("bt")
        endif
    endif

    call state#Switch('gdb', 'pause', 0)
endfunction


function! s:prototype.on_accept(port, ...)
    if a:port
        let self._server_addr[1] = a:port
        call self.Attach()
    endif
endfunction


function s:prototype.on_remote_debugging(...)
    let self._remote_debugging = 1
    call state#Switch('gdb', 'pause', 0)
endfunction


function! s:prototype.on_remoteconn_succ(...)
    call state#Switch('gdb', 'pause', 0)
endfunction


function! s:prototype.on_remoteconn_fail(...)
    silent! call s:log.error("Remote connect gdbserver fail!")
endfunction


function! s:prototype.on_pause(...)
    call state#Switch('gdb', 'pause', 0)
endfunction


function! s:prototype.on_disconnected(...)
    if !self._server_exited && self._reconnect
        " Refresh to force a delete of all watchpoints
        "call self.RefreshBreakpoints(2)
        sleep 1
        call self.Attach()
        call self.Send('continue')
    endif
endfunction

function! s:prototype.on_exit(...)
    let self._server_exited = 1
endfunction


function! s:prototype.Map(type)
    "{
    if a:type ==# "unmap"
        exe 'unmap ' . g:gdb_keymap_refresh
        exe 'unmap ' . g:gdb_keymap_continue
        exe 'unmap ' . g:gdb_keymap_next
        exe 'unmap ' . g:gdb_keymap_step
        exe 'unmap ' . g:gdb_keymap_finish
        exe 'unmap ' . g:gdb_keymap_clear_break
        exe 'unmap ' . g:gdb_keymap_debug_stop
        exe 'unmap ' . g:gdb_keymap_until
        exe 'unmap ' . g:gdb_keymap_toggle_break
        exe 'unmap ' . g:gdb_keymap_toggle_break_all
        exe 'vunmap ' . g:gdb_keymap_toggle_break
        exe 'cunmap ' . g:gdb_keymap_toggle_break
        exe 'unmap ' . g:gdb_keymap_frame_up
        exe 'unmap ' . g:gdb_keymap_frame_down
        exe 'tunmap ' . g:gdb_keymap_refresh
        exe 'tunmap ' . g:gdb_keymap_continue
        exe 'tunmap ' . g:gdb_keymap_next
        exe 'tunmap ' . g:gdb_keymap_step
        exe 'tunmap ' . g:gdb_keymap_finish
        exe 'tunmap ' . g:gdb_keymap_toggle_break_all

        if exists("*NeogdbvimUnmapCallback")
            call NeogdbvimUnmapCallback()
        endif
    elseif a:type ==# "tmap"
        exe 'tnoremap <silent> ' . g:gdb_keymap_refresh . ' <c-\><c-n>:GdbRefresh<cr>i'
        exe 'tnoremap <silent> ' . g:gdb_keymap_continue . ' <c-\><c-n>:GdbContinue<cr>i'
        exe 'tnoremap <silent> ' . g:gdb_keymap_next . ' <c-\><c-n>:GdbNext<cr>i'
        exe 'tnoremap <silent> ' . g:gdb_keymap_step . ' <c-\><c-n>:GdbStep<cr>i'
        exe 'tnoremap <silent> ' . g:gdb_keymap_finish . ' <c-\><c-n>:GdbFinish<cr>i'
        exe 'tnoremap <silent> ' . g:gdb_keymap_toggle_break_all . ' <c-\><c-n>:GdbToggleBreakAll<cr>i'
    elseif a:type ==# "nmap"
        exe 'nnoremap <silent> ' . g:gdb_keymap_refresh . ' :GdbRefresh<cr>'
        exe 'nnoremap <silent> ' . g:gdb_keymap_continue . ' :GdbContinue<cr>'
        exe 'nnoremap <silent> ' . g:gdb_keymap_next . ' :GdbNext<cr>'
        exe 'nnoremap <silent> ' . g:gdb_keymap_step . ' :GdbStep<cr>'
        exe 'nnoremap <silent> ' . g:gdb_keymap_finish . ' :GdbFinish<cr>'
        exe 'nnoremap <silent> ' . g:gdb_keymap_until . ' :GdbUntil<cr>'

        let toggle_break_binding = 'nnoremap <silent> ' . g:gdb_keymap_toggle_break . ' :GdbToggleBreak<cr>'
        if !g:gdb_require_enter_after_toggling_breakpoint
            let toggle_break_binding = toggle_break_binding . '<cr>'
        endif
        exe toggle_break_binding

        exe 'nnoremap <silent> ' . g:gdb_keymap_toggle_break_all . ' :GdbToggleBreakAll<cr>'
        exe 'cnoremap <silent> ' . g:gdb_keymap_toggle_break . ' <cr>'
        exe 'vnoremap <silent> ' . g:gdb_keymap_toggle_break . ' :GdbEvalRange<cr>'
        exe 'nnoremap <silent> ' . g:gdb_keymap_clear_break . ' :GdbClearBreak<cr>'
        exe 'nnoremap <silent> ' . g:gdb_keymap_debug_stop . ' :GdbDebugStop<cr>'
        exe 'nnoremap <silent> ' . g:gdb_keymap_frame_up . ' :GdbFrameUp<cr>'
        exe 'nnoremap <silent> ' . g:gdb_keymap_frame_down . ' :GdbFrameDown<cr>'

        if exists("*NeogdbvimNmapCallback")
            call NeogdbvimNmapCallback()
        endif
    endif
    "}
endfunction


