# Those functions are copied from newer kexec-tools, only used here as
# backward compatiblity for testing older kexec-tools. Since for newer
# kexec-tools, we can always import them via import_functions()

KDUMP_CONFIG_FILE="/etc/kdump.conf"
_set_config()
{
	local opt=$1
	local val=$2

	if [[ -z $val ]]; then
		derror "Invalid kdump config value for option '$opt'"
		return 1
	fi

	if [[ -n ${OPT[$opt]} ]]; then
		if [[ $opt == _target ]] || [[ $opt == _fstype ]]; then
			derror "More than one dump targets specified"
		else
			derror "Duplicated kdump config value of option $opt"
		fi
		return 1
	fi
	OPT[$opt]="$val"
}

# deleted "check_*_config || return 1" lines
parse_config()
{
	while read -r config_opt config_val; do
		case "$config_opt" in
		dracut_args)
			if [[ $config_val == *--mount* ]]; then
				if [[ $(echo "$config_val" | grep -o -- "--mount" | wc -l) -ne 1 ]]; then
					derror 'Multiple mount targets specified in one "dracut_args".'
					return 1
				fi
				_set_config _fstype "$(get_dracut_args_fstype "$config_val")" || return 1
				_set_config _target "$(get_dracut_args_target "$config_val")" || return 1
			fi
			;;
		raw)
			if [[ -d "/proc/device-tree/ibm,opal/dump" ]]; then
				dwarn "WARNING: Won't capture opalcore when 'raw' dump target is used."
			fi
			_set_config _fstype "$config_opt" || return 1
			config_opt=_target
			;;
		ext[234] | minix | btrfs | xfs | nfs | ssh | virtiofs)
			_set_config _fstype "$config_opt" || return 1
			config_opt=_target
			;;
		sshkey)
			if [[ -z $config_val ]]; then
				derror "Invalid kdump config value for option '$config_opt'"
				return 1
			elif [[ -f $config_val ]]; then
				config_val=$(/usr/bin/readlink -m "$config_val")
			else
				dwarn "WARNING: '$config_val' doesn't exist, using default value '$DEFAULT_SSHKEY'"
				config_val=$DEFAULT_SSHKEY
			fi
			;;
		default)
			dwarn "WARNING: Option 'default' was renamed 'failure_action' and will be removed in the future."
			dwarn "Please update $KDUMP_CONFIG_FILE to use option 'failure_action' instead."
			_set_config failure_action "$config_val" || return 1
			;;
		path | core_collector | kdump_post | kdump_pre | extra_bins | extra_modules | failure_action | final_action | force_rebuild | force_no_rebuild | fence_kdump_args | fence_kdump_nodes | auto_reset_crashkernel) ;;

		net | options | link_delay | disk_timeout | debug_mem_level | blacklist)
			derror "Deprecated kdump config option: $config_opt. Refer to kdump.conf manpage for alternatives."
			return 1
			;;
		'')
			continue
			;;
		*)
			derror "Invalid kdump config option $config_opt"
			return 1
			;;
		esac

		_set_config "$config_opt" "$config_val" || return 1
	done <<< "$(kdump_read_conf)"

	OPT[path]=${OPT[path]:-$DEFAULT_PATH}
	OPT[sshkey]=${OPT[sshkey]:-$DEFAULT_SSHKEY}

	return 0
}

get_reserved_mem_size()
{
	local reserved_mem_size=0

	if is_fadump_capable; then
		reserved_mem_size=$(< /sys/kernel/fadump/mem_reserved)
	else
		reserved_mem_size=$(< /sys/kernel/kexec_crash_size)
	fi

	echo "$reserved_mem_size"
}

is_kernel_loaded()
{
	local _sysfs _mode

	_mode=$1

	case "$_mode" in
	kdump)
		_sysfs="/sys/kernel/kexec_crash_loaded"
		;;
	fadump)
		_sysfs="$FADUMP_REGISTER_SYS_NODE"
		;;
	*)
		derror "Unknown dump mode '$_mode' provided"
		return 1
		;;
	esac

	if [[ ! -f $_sysfs ]]; then
		derror "$_mode is not supported on this kernel"
		return 1
	fi

	[[ $(< $_sysfs) -eq 1 ]]
}

kdump_read_conf()
{
	[ -f "$KDUMP_CONFIG_FILE" ] && sed -n -e "s/#.*//;s/\s*$//;s/^\s*//;s/\(\S\+\)\s*\(.*\)/\1 \2/p" $KDUMP_CONFIG_FILE
}

kdump_get_conf_val()
{
	[ -f "$KDUMP_CONFIG_FILE" ] &&
		sed -n -e "/^\s*\($1\)\s\+/{s/^\s*\($1\)\s\+//;s/#.*//;s/\s*$//;h};\${x;p}" $KDUMP_CONFIG_FILE
}