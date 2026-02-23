#!/bin/bash
p="$1"
git -C "$p" rev-parse --git-dir >/dev/null 2>&1 || exit 0
git -C "$p" diff HEAD --shortstat 2>/dev/null | awk '/changed/{
  f=$1
  for(i=1;i<=NF;i++){
    if($i~/insertion/){a=$(i-1)}
    if($i~/deletion/){d=$(i-1)}
  }
  if(f+0>0){
    printf "%s file%s", f, (f==1?"":"s")
    if(a+0>0) printf " +%s", a
    if(d+0>0) printf " -%s", d
  }
}'
