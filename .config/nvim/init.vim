set runtimepath^=~/.vim
set runtimepath+=~/.vim/after

let &packpath=&runtimepath
source ~/.vimrc

" .............................................................................
" nvim-treesitter/nvim-treesitter
" .............................................................................

" Toggle highlight
map <Leader><F1> :TSToggle highlight<CR>
