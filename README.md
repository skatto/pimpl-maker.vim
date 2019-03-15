# pimpl-maker.vim #

Vim plugin which helps you make pimpl pattern in c++ code.  

## Usage ##
Exanple of `.vimrc`

```vim
let g:pimplmaker_impl_class_name = 'Impl'       " set the class name for pimpl pattern.
let g:pimplmaker_pimpl_instance_name = 'pimpl'  " set the member variable name for pimpl pattern.
nnoremap <C-p> :PimplMake<CR>                   " make pimpl pattern for the class with the current cursor
```

## Screenshot ##
One command! (left to right)

<img src="https://raw.githubusercontent.com/skatto/pimpl-maker.vim/master/screenshots/1.png">

## Others ##
This plugin is tested on few environments.

I hope your pull requests.
