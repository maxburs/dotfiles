export PS1="\W$(if [ \$? != 0 ]; then echo \" [$?]\"; fi)\$ "
