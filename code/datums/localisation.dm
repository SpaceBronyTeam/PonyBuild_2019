//� ������ ����� ��������� �������� �� ������ ���� �� ������. ������ ������ ����� 2 ������� � ������������ ������

var/list/localisation_languages = list("eng", "ru")

var/list/localisation_lists = list()//��� �������� �������





datum/localisation_global
	var/lang
	var/list/ids = list() //"" = ""

	New(var/n)	// 1 - � ���� ��������� ���� ���, ������ ��� ����� � ������ ���� "�� ����������" = "�� ������"
		lang = n

		LoadIDFromData() // 2 - ������� ������������ ����� �� ����� ���� �����������

	proc/LoadIDFromData()
		var/text = file2text("data/localisation/[lang].txt")

		//������ ����� �������� �� �����
		while(findtext(text, "\"") && findtext(text, "="))
			var/first_pos = findtext(text, "\"")+1

			var/l1 = copytext(text, first_pos, findtext(text, "\"", first_pos))//��������� ��������� �������

			text = copytext(text, findtext(text, "=")+1)

			first_pos = findtext(text, "\"")+1
			var/l2 = copytext(text, first_pos, findtext(text, "\"", first_pos))

			ids[l1] = l2

			text = copytext(text, findtext(text, "\"", 2) + min(2, lentext(text)-findtext(text, "\"", 2)) )



	proc/LocalIDCompareWith(var/datum/localisation_global/LG2)//� ������ �������� ����� ������ ������������ ���������, ��� ���������� ����������� �������
		for(var/label in LG2.ids)
			if(!(label in ids))
				LocalAddLabel(label)//������ ������� ��������� � ��������� ������

	proc/LocalAddLabel(var/label)//���������� ���� ������ ��� �� �������� - ���������� ����� ������ � ���� �����������, ����� � ��������
		var/text = file2text("data/localisation/[lang].txt")
		var/add_text = "\"[label]\"=\"\""
		if(!findtext(text, add_text))
			text2file("[add_text]", "data/localisation/[lang].txt")





/world/New()
	..()
	for(var/lang in localisation_languages-"eng")	// 0 - ��� �������� ���� ��������� ��������� �������� ������������ ����
		var/datum/localisation_global/LG = new(lang)
		localisation_lists += list(lang = LG)

	for(var/datum/localisation_global/LG1 in localisation_lists)
		for(var/datum/localisation_global/LG2 in localisation_lists-LG1)
			LG1.LocalIDCompareWith(LG2)


proc/local(var/id_text, var/language, var/base_language)
	if(!language) //������ �� ��, ��� �� �������� ������ ��� ��������� ������ ��������
		language = (usr) ? ((usr.client.language) ? usr.client.language : "eng") : "eng"

	if(language=="eng")//���� ���� � ������ ���������� ���� - ������ ����������� ��� ����� ��������� ���� ������
		for(var/L in localisation_lists)
			var/datum/localisation_global/LG1 = localisation_lists[L]
			if(!(id_text in LG1.ids))
				LG1.LocalAddLabel(id_text)
		return id_text

	var/datum/localisation_global/LG// ���������� ������ ��� ������� �����
	for(var/lang in localisation_lists)
		var/datum/localisation_global/LG1 = localisation_lists[lang]
		if(LG1.lang==language)
			LG=LG1
			break

	if(id_text in LG.ids)
		if(!LG.ids[id_text] || LG.ids[id_text]=="")//���� ������ �����, �� ���������� ���������� ��������
			return id_text
		else
			return LG.ids[id_text]//����� �����������
	else
		for(var/L in localisation_lists)
			var/datum/localisation_global/LG1 = localisation_lists[L]
			if(!(id_text in LG1.ids))
				LG1.LocalAddLabel(id_text)//���� ������ ������ �� ����������, �� ���� ������ �����������
		return id_text