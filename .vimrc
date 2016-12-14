set nocp
set tabstop=4
set shiftwidth=4
set hlsearch
filetype plugin indent on
syntax on

" Pathogen
call pathogen#infect()
call pathogen#helptags()
" Pathogen load alternative
"filetype off " Pathogen needs to run before plugin indent on
"call pathogen#runtime_append_all_bundles()
"call pathogen#helptags() " generate helptags for everything in 'runtimepath'
"filetype plugin indent on

