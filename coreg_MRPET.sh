#!/bin/bash
# ANTs coregistration: structural whole brain, structural slab, functional slab/whole brain, LC mask

# the subject folders
path=/mnt/work/yyi/temp/ED_coreg/MRPET

# MNI template with filename
MNI=/mnt/work/yyi/temp/ED_coreg/mni_icbm152_t1_tal_nlin_asym_09c.nii

# template with filename
template=/mnt/work/yyi/temp/ED_coreg/hc_template.nii.gz

# assign number of CPUs used
CPUs=3

# subject folders in ${path}
ls -d "${path}"/*/ > "${path}"/subj_mrpet.txt

# template -> MNI non-linear registration
antsRegistrationSyN.sh -d 3 -n "${CPUs}" -t s -f "${MNI}" -m "${template}" -o "${path}"/NLreg_template_to_MNI_

while read folder; do

	# subject ID
	ID=$(echo "${folder}" | grep -o -E '[0-9][0-9][0-9][0-9][0-9]')

	# bias field correction on the whole brain t1
	N4BiasFieldCorrection -d 3 -v 1 -r 0 -i "${folder}"data/T1WB.nii -o "${folder}"data/T1WB_corrected.nii -s 2 -c [200x150x100x50,1e-6] -b 200

	# Resample structural slab to 1 mm isotropic (uses FreeSurfer)
	mri_convert -cs 1 -odt float -rl "${folder}"data/T1WB.nii -rt cubic "${folder}"data/t1slab.nii "${folder}"data/t1slab_1mm.nii

	# Resample mask to 1 mm isotropic (uses FreeSurfer)
	mri_convert -cs 1 -odt float -rl "${folder}"data/T1WB.nii -rt cubic "${folder}"data/LCmask_"${ID}".nii.gz "${folder}"data/LCmask_"${ID}"_mask_1mm_backup.nii

	# Threshold mask from 0.1 to 100 setting it to 1 at every voxel (uses FreeSurfer)
	mri_binarize --i "${folder}"data/LCmask_"${ID}"_mask_1mm_backup.nii --o "${folder}"data/LCmask_"${ID}"_mask_1mm.nii --min 0.1

	# Make a mask of structural slab (uses FreeSurfer)
	mri_binarize --i "${folder}"data/t1slab_1mm.nii --o "${folder}"data/t1slab_1mm_mask.nii --min 200

	# Make a mask of EPI (uses FreeSurfer)
	mri_binarize --i "${folder}"data/meanMRI.nii --o "${folder}"data/meanMRI_mask.nii --min 500

	# LC mask
	mask=$(ls -t "${folder}"data/LCmask_"${ID}".nii.gz)

	# ******************************

	# EPI -> WB (rigid)
	antsRegistrationSyN.sh -d 3 -n "${CPUs}" -t r -f "${folder}"data/T1WB_corrected.nii -m "${folder}"data/meanMRI.nii -x "${folder}"data/meanMRI_mask.nii -o "${folder}"data/coreg_meanMRI_to_T1WB_

	# t1slab -> WB (rigid)
	antsRegistrationSyN.sh -d 3 -n "${CPUs}" -t r -f "${folder}"data/T1WB_corrected.nii -m "${folder}"data/t1slab_1mm.nii -x "${folder}"data/t1slab_1mm_mask.nii -o "${folder}"data/coreg_t1slab_to_T1WB_

	# WB -> template
  antsRegistrationSyN.sh -d 3 -n "${CPUs}" -t s -f "${template}" -m "${folder}"data/T1WB_corrected.nii -o "${folder}"data/NLreg_T1WB_to_template_

	# WB -> MNI non-linearly
	antsApplyTransforms -d 3 -v 1 -n BSpline[4] -t "${path}"/NLreg_template_to_MNI_1Warp.nii.gz -t "${path}"/NLreg_template_to_MNI_0GenericAffine.mat -t "${folder}"data/NLreg_T1WB_to_template_1Warp.nii.gz -t "${folder}"data/NLreg_T1WBto_template_0GenericAffine.mat --float 1 -i "${folder}"data/T1WB_corrected.nii -r "${MNI}" -o "${folder}"data/NLreg_T1WB_to_MNI.nii

	# EPI -> template non-linearly
	antsApplyTransforms -d 3 -v 1 -n Linear -t "${folder}"data/NLreg_T1WBto_template_1Warp.nii.gz -t "${folder}"data/NLreg_T1WBto_template_0GenericAffine.mat -t "${folder}"data/coreg_meanMRI_to_T1WB_0GenericAffine.mat --float 1 -i "${folder}"data/meanMRI.nii -r "${template}" -o "${folder}"data/NLreg_meanMRI_to_template.nii

	# EPI -> MNI
	antsApplyTransforms -d 3 -v 1 -n Linear -t "${path}"/NLreg_template_to_MNI_1Warp.nii.gz -t "${path}"/NLreg_template_to_MNI_0GenericAffine.mat -t "${folder}"data/NLreg_T1WB_to_template_1Warp.nii.gz -t "${folder}"data/NLreg_T1WB_to_template_0GenericAffine.mat -t "${folder}"data/coreg_meanMRI_to_T1WB_0GenericAffine.mat --float 1 -i "${folder}"data/meanMRI.nii -r "${MNI}" -o "${folder}"data/NLreg_meanMRI_to_MNI.nii

	# apply transformation: mask -> WB (rigid)
	antsApplyTransforms -d 3 -v 1 -n Linear -t "${folder}"data/coreg_t1slab_to_T1WB_0GenericAffine.mat --float 1 -i "${mask}" -r "${folder}"data/T1WB_corrected.nii -o "${folder}"data/coreg_LCmask_to_T1WB.nii

	# threshold & binarise mask from 0.1 to 100 setting it to 1 at every voxel (uses FreeSurfer)
 	mri_binarize --i "${folder}"data/coreg_LCmask_to_T1WB.nii --o "${folder}"data/coreg_LCmask_to_T1WB_binarized.nii --min 0.1

	# mask -> template
	antsApplyTransforms -d 3 -v 1 -n Linear -t "${folder}"data/NLreg_T1WB_to_template_1Warp.nii.gz -t "${folder}"data/NLreg_T1WB_to_template_0GenericAffine.mat -t "${folder}"data/coreg_t1slab_to_T1WB_0GenericAffine.mat --float 1 -i "${mask}" -r "${template}" -o "${folder}"data/NLreg_LCmask_to_template.nii

	# Threshold mask from 0.1 to 100 setting it to 1 at every voxel (uses FreeSurfer)
	mri_binarize --i "${folder}"data/NLreg_LCmask_to_template.nii --o "${folder}"data/NLreg_LCmask_to_template_binarized.nii --min 0.1

	# mask -> MNI
	antsApplyTransforms -d 3 -v 1 -n Linear -t "${path}"/NLreg_template_to_MNI_1Warp.nii.gz -t "${path}"/NLreg_template_to_MNI_0GenericAffine.mat -t "${folder}"data/NLreg_T1WB_to_template_1Warp.nii.gz -t "${folder}"data/NLreg_T1WB_to_template_0GenericAffine.mat -t "${folder}"data/coreg_t1slab_to_T1WB_0GenericAffine.mat --float 1 -i "${mask}" -r "${MNI}" -o "${folder}"data/NLreg_LCmask_to_MNI.nii

	# threshold & binarise mask from 0.1 to 100 setting it to 1 at every voxel
	mri_binarize --i "${folder}"data/NLreg_LCmask_to_MNI.nii --o "${folder}"data/NLreg_LCmask_to_MNI_binarized.nii --min 0.1

	########### work on contrast coregistration #############

	for I in 01 02 03 04 05 06 07 08 09 10 11 12 13
	do
		antsApplyTransforms -d 3 -v 1 -n Linear -t "${path}"/NLreg_template_to_MNI_1Warp.nii.gz -t "${path}"/NLreg_template_to_MNI_0GenericAffine.mat -t "${folder}"data/NLreg_T1WB_to_template_1Warp.nii.gz -t "${folder}"data/NLreg_T1WB_to_template_0GenericAffine.mat -t ["${folder}"data/coreg_T1WB_to_meanMRI_0GenericAffine.mat, 1] -i "${folder}"data/con_00${I}.nii -r "${MNI}" -o "${folder}"data/con_00${I}_mni.nii
	done
	# move contrast mask
	antsApplyTransforms -d 3 -v 1 -n Linear -t "${path}"/NLreg_template_to_MNI_1Warp.nii.gz -t "${path}"/NLreg_template_to_MNI_0GenericAffine.mat -t "${folder}"NLreg_T1WB_to_template_1Warp.nii.gz -t "${folder}"NLreg_T1WB_to_template_0GenericAffine.mat -t ["${folder}"coreg_T1WB_to_meanMRI_0GenericAffine.mat, 1] -i "${folder}"data/mask.nii -r "${MNI}" -o "${folder}"data/mask_mni.nii

	############## work on PET coregistration ###############

	# PET -> WB
	#antsApplyTransforms -d 3 -e 3 -n Linear -t ["${folder}"data/coreg_meanMRI_to_T1WB_0GenericAffine.mat, 1] -v 1 --float 1 -i "${folder}"data/meanPET.nii -r "${folder}"data/T1WB_corrected.nii -o "${folder}"data/coreg_meanPET_to_T1WB.nii.gz

	# PET -> MNI
	#antsApplyTransforms -d 3 -e 3 -v 1 -n Linear -t "${path}"/NLreg_template_to_MNI_1Warp.nii.gz -t "${path}"/NLreg_template_to_MNI_0GenericAffine.mat -t "${folder}"data/NLreg_T1WB_to_template_1Warp.nii.gz -t "${folder}"data/NLreg_T1WB_to_template_0GenericAffine.mat -t ["${folder}"data/coreg_meanMRI_to_T1WB_0GenericAffine.mat, 1] -i "${folder}"data/meanPET.nii -r "${MNI}" -o "${folder}"data/NLreg_meanPET_to_MNI.nii.gz

  echo "ID ${ID} DONE!"

done < "${path}"/subj_mrpet.txt
