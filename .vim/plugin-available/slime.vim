
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function Send_to_Screen(text)
  if !exists("g:screen_sessionname") || !exists("g:screen_windowname")
    call Screen_Vars()
  endif
"echo "Sending to session: " . g:screen_sessionname " window: " . g:screen_windowname
"sleep 1
    silent exe "!screen -S " . g:screen_sessionname . " -p " . g:screen_windowname . " -X stuff " . shellescape(a:text) 
endfunction

function Screen_Session_Names(A,L,P)
  return system("screen -ls | awk '/Attached/ {print $1}'")
endfunction

function Screen_Vars()
" this let is not assigning correctly
" http://vimdoc.sourceforge.net/htmldoc/eval.html#input()
" http://vimdoc.sourceforge.net/htmldoc/map.html#:command-completion
  let g:screen_sessionname = input("session name: ", "", "custom,Screen_Session_Names")
echo Screen_Session_Names("A","L","P")
sleep 1
  let g:screen_windowname = input("window name: ", "0")
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

vmap <C-c><C-c> "ry :call Send_to_Screen(@r)<CR>
nmap <C-c><C-c> vip<C-c><C-c>

nmap <C-c>v :call Screen_Vars()<CR>

